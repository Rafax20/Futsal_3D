class_name Portero
extends RefCounted

## Módulo Reglamentario y de IA de Portero de Fútsal (FIFA / AMF):
## - Regla de Cesión al Portero (Prohibición de Manos tras pase intencional con el pie de un compañero):
##   * Si un compañero pasa el balón con el pie al arquero, el arquero NO puede agarrarlo con las manos;
##     únicamente puede controlar o despejar con los pies.
##   * Si el portero toca el balón con las manos tras cesión con el pie de un compañero, el árbitro
##     sanciona Tiro Libre Indirecto a favor del rival desde la línea del área de 6 metros.
## - Técnica de Portero de Fútsal: Achique en Cruz / "K" (Técnica Canaria), atajadas bajas con pies
##   estilo Hockey (abanico/espagat) y bloqueo rígido de pecho/rostro.


## Retorna true únicamente si el portero está dentro de su propia área penal Y el balón NO proviene
## de una cesión o pase con el pie de un compañero de equipo.
static func puede_usar_manos(portero: Jugador3D, balon: Balon3D) -> bool:
	if portero == null or balon == null:
		return false
	if portero.posicion_tactica != "PORTERO":
		return false
	if not portero._esta_en_area_propia(balon.global_position):
		return false
	# Solo se prohíbe si un compañero de campo le pasó intencionalmente el balón con el pie (flag de Balon3D).
	# Los rebotes de sus propias atajadas o desvíos rivales sí pueden atraparse con las manos.
	if balon.prohibido_manos_portero(int(portero.equipo)):
		return false
	return true


## Valida si una captura con las manos infringe la Regla de Cesión al Portero.
## Si existe cesión con el pie de un compañero, sanciona Tiro Libre Indirecto desde el borde del área y retorna true.
static func verificar_y_sancionar_cesion_manos(portero: Jugador3D, balon: Balon3D) -> bool:
	if portero == null or balon == null:
		return false
	if balon.prohibido_manos_portero(int(portero.equipo)):
		balon.registrar_toque_cesion_pie(false, -1)
		var arbol: SceneTree = portero.get_tree()
		if arbol != null:
			var gestor: GestorPartido = arbol.get_first_node_in_group("gestor_partido") as GestorPartido
			if gestor != null:
				gestor.sancionar_cesion_portero_manos(int(portero.equipo), portero.global_position)
		return true
	return false


## Gestiona la recepción reglamentaria del balón por parte del portero:
## - Si proviene de un pase con el pie de un compañero (cesión), solo controla o despeja con los pies.
## - Si proviene del rival dentro del área propia, asegura con las manos.
static func procesar_recepcion(portero: Jugador3D, balon: Balon3D) -> void:
	if portero == null or balon == null:
		return
	
	var es_cesion_amigo: bool = balon.prohibido_manos_portero(int(portero.equipo))
	if es_cesion_amigo:
		# Regla Futsal: Prohibido agarrar con las manos tras pase de compañero; jugar exclusivamente con los pies
		portero._t_anim_patada = 0.24
		var presion: float = portero.calcular_presion_rival()
		if not portero.es_controlado and presion > 0.48:
			despejar_con_pie(portero, balon)
		else:
			portero.tomar_posesion(balon)
			portero.tiene_balon_en_manos = false
			if int(portero.equipo) == 0:
				portero._emitir_anuncio_hud("¡CESIÓN AL PORTERO! SOLO PUEDE JUGAR CON EL PIE")
		return
	
	if puede_usar_manos(portero, balon):
		portero.atrapar_con_manos(balon)
	else:
		portero.tomar_posesion(balon)


## Ejecuta un despeje o pase rápido con el pie cuando el portero recibe una cesión bajo presión rival
static func despejar_con_pie(portero: Jugador3D, balon: Balon3D) -> void:
	if portero == null or balon == null:
		return
	
	portero._t_anim_patada = 0.28
	portero._t_bloqueo_recaptura = 0.45
	var dir_ataque_x: float = 1.0 if int(portero.equipo) == 0 else -1.0
	var dir_base: Vector3 = Vector3(dir_ataque_x, 0.0, 0.0)
	var mejor_comp: Jugador3D = portero._buscar_mejor_receptor(dir_base)
	
	if mejor_comp != null:
		var hacia_comp: Vector3 = mejor_comp.global_position - balon.global_position
		hacia_comp.y = 0.0
		var dist_c: float = hacia_comp.length()
		var dir_pase: Vector3 = hacia_comp.normalized() if dist_c > 0.1 else dir_base
		var fuerza_pase: float = clampf(dist_c * 1.15 + 4.5, 9.0, 17.5)
		balon.liberar(dir_pase * fuerza_pase + Vector3(0.0, 0.18, 0.0), int(portero.equipo), false)
	else:
		var z_banda: float = 0.42 if portero.global_position.z >= 0.0 else -0.42
		var dir_despeje: Vector3 = Vector3(dir_ataque_x, 0.28, z_banda).normalized()
		balon.liberar(dir_despeje * 15.5, int(portero.equipo), false)
	
	if int(portero.equipo) == 0:
		portero._emitir_anuncio_hud("¡DESPEJE CON EL PIE DEL ARQUERO!")


# ==============================================================================
# GEOMETRÍA DE BISECTRIZ Y ACHIQUE DE FUTSAL REAL (ARCO 3x2 M)
# ==============================================================================

const RADIO_PIERNA: float = 0.13
const RADIO_TORSO: float = 0.22
const RADIO_BRAZO: float = 0.13


## Calcula la posición óptima del arquero sobre la bisectriz geométrica del arco
## (entre el centro del arco y los dos postes ±1.5m respecto al balón):
## - Si el balón está lejos (> 9.0 m): no sale más de 1.2 a 1.6 m para no quedar expuesto a vaselina.
## - Si está en zona intermedia (4.5 a 9.0 m): adelanta entre 1.6 y 2.4 m.
## - Si está a quemarropa (< 4.5 m): achica hasta 3.0 m manteniendo 2.0 a 2.8 m respecto al balón.
static func calcular_posicion_bisectriz(linea_meta_x: float, pos_balon: Vector3, gk_posicionamiento: float) -> Vector3:
	var centro_arco: Vector3 = Vector3(linea_meta_x, 0.0, 0.0)
	var p_b: Vector3 = Vector3(pos_balon.x, 0.0, pos_balon.z)
	
	var poste_izq: Vector3 = Vector3(linea_meta_x, 0.0, -1.5)
	var poste_der: Vector3 = Vector3(linea_meta_x, 0.0, 1.5)
	
	var v_izq: Vector3 = (poste_izq - p_b).normalized()
	var v_der: Vector3 = (poste_der - p_b).normalized()
	var dir_bisectriz: Vector3 = -(v_izq + v_der)
	dir_bisectriz.y = 0.0
	
	if dir_bisectriz.length_squared() < 0.001:
		dir_bisectriz = (p_b - centro_arco)
		dir_bisectriz.y = 0.0
	if dir_bisectriz.length_squared() < 0.001:
		dir_bisectriz = Vector3(1.0 if linea_meta_x < 0.0 else -1.0, 0.0, 0.0)
	dir_bisectriz = dir_bisectriz.normalized()
	
	var dist_balon_arco: float = centro_arco.distance_to(p_b)
	var factor_pos: float = clampf(gk_posicionamiento / 99.0, 0.5, 1.0)
	
	var avance: float = 1.35
	if dist_balon_arco > 9.0:
		avance = lerpf(1.20, 1.60, factor_pos)
	elif dist_balon_arco >= 4.5:
		var t_dist: float = (dist_balon_arco - 4.5) / 4.5
		avance = lerpf(2.50, 1.60, t_dist) * factor_pos
	else:
		avance = clampf(dist_balon_arco * 0.65, 1.60, 3.00) * factor_pos
	
	avance = clampf(avance, 1.20, 3.00)
	
	var pos_deseada: Vector3 = centro_arco + dir_bisectriz * avance
	pos_deseada.y = 0.0
	pos_deseada.z = clampf(pos_deseada.z, -1.65, 1.65)
	
	if linea_meta_x < 0.0:
		pos_deseada.x = clampf(pos_deseada.x, -19.4, -15.5)
	else:
		pos_deseada.x = clampf(pos_deseada.x, 15.5, 19.4)
	
	return pos_deseada


## Evalúa la lectura de Mano a Mano (1vs1):
## Si distancia < 4.2m, el arquero "aguanta" en Guardia Baja a 2.0 - 2.8m y NO se tira al piso antes de tiempo;
## solo despliega La Cruz (K-Block) cuando el delantero arma el disparo o intenta avanzar a menos de 2.4m.
static func evaluar_lectura_mano_a_mano(dist_al_balon: float, disparo_inminente: bool, tiempo_cruz_activo: float) -> bool:
	if tiempo_cruz_activo > 0.0:
		return true
	if dist_al_balon < 4.2 and (disparo_inminente or dist_al_balon < 2.4):
		return true
	return false
