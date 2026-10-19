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
