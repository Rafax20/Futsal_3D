class_name GestorPartido
extends Node

## Gestor de Reglas Oficiales de Futsal (FIFA / AMF):
## - Secuencia de entrada desde banquillos (ENTRADA_EQUIPOS).
## - Reloj Neto de Futsal (2 tiempos): solo avanza en EN_JUEGO.
## - Regla estricta de los 4 Segundos en saques de banda, esquina y meta (concede posesión al rival si vence).
## - Acumulación de faltas por tiempo y Doble Penalti desde 10m sin barrera a partir de la 6ª falta.
## - Saque de banda detenido con el pie sobre la línea y saque de meta con la mano del portero.
## - Tiempo muerto (1 por tiempo para el equipo con posesión del balón).

enum EstadoPartido {
	ENTRADA_EQUIPOS,
	SAQUE_CENTRO,
	EN_JUEGO,
	SAQUE_BANDA,
	SAQUE_META,
	SAQUE_ESQUINA,
	TIRO_LIBRE,
	DOBLE_PENALTI,
	TIEMPO_MUERTO,
	GOL
}

signal estado_cambiado(nuevo: EstadoPartido)
signal cuenta_regresiva_4s_actualizada(segundos_restantes: float, activa: bool)
signal posesion_cambiada(en_ataque_local: bool, equipo_poseedor: int)

@export var distancia_reglamentaria: float = 4.0
@export var radio_circulo_central: float = 3.0
@export var margen_distancia: float = 0.3
@export var t_pausa_saque: float = 0.65
@export var t_celebracion_gol: float = 2.0
@export var t_timeout_saque: float = 4.0
@export var t_duracion_entrada: float = 2.4
@export var t_duracion_tiempo_muerto: float = 3.5

var estado: EstadoPartido = EstadoPartido.ENTRADA_EQUIPOS
var _balon: Balon3D = null
var _sacador_actual: Jugador3D = null
var _equipo_sacador: int = 0
var _timer_timeout: float = 0.0
var _esperando_toque: bool = false
var _pos_saque: Vector3 = Vector3.ZERO
var _sancionando_4s: bool = false
var _en_ataque_local_actual: bool = true
var _equipo_poseedor_actual: int = 0


func _ready() -> void:
	add_to_group("gestor_partido")
	_conectar_balon()
	if GameManager and not GameManager.fin_primer_tiempo.is_connected(_on_fin_primer_tiempo):
		GameManager.fin_primer_tiempo.connect(_on_fin_primer_tiempo)
	call_deferred("iniciar_entrada_equipos")


func _conectar_balon() -> void:
	var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
	if not balones.is_empty():
		_balon = balones[0] as Balon3D
		if _balon and not _balon.balon_liberado.is_connected(_on_balon_liberado):
			_balon.balon_liberado.connect(_on_balon_liberado)


func _cambiar_estado(nuevo_estado: EstadoPartido) -> void:
	estado = nuevo_estado
	if GameManager:
		# El reloj neto de 20:00 solo avanza cuando el balón está efectivamente en juego (EN_JUEGO)
		GameManager.reloj_neto_activo = (estado == EstadoPartido.EN_JUEGO)
	estado_cambiado.emit(estado)
	_actualizar_estado_posesion_hud(true)


## Retorna true si el equipo local (usuario) está en modo ataque/posesión para el HUD táctil
func es_ataque_local() -> bool:
	return _en_ataque_local_actual


## Evalúa en tiempo real si el equipo local está en fase ofensiva (Ataque) o defensiva (Sin Balón) y emite señal al HUD
func _actualizar_estado_posesion_hud(forzar_emision: bool = false) -> void:
	if _balon == null:
		return
	
	var nuevo_ataque_local: bool = _en_ataque_local_actual
	var nuevo_poseedor: int = _equipo_poseedor_actual
	
	if estado != EstadoPartido.EN_JUEGO and _esperando_toque:
		nuevo_poseedor = _equipo_sacador
		nuevo_ataque_local = (_equipo_sacador == 0)
	elif _balon.sacador_autorizado != null and is_instance_valid(_balon.sacador_autorizado):
		nuevo_poseedor = int(_balon.sacador_autorizado.equipo)
		nuevo_ataque_local = (nuevo_poseedor == 0)
	elif _balon.esta_siendo_conducido() and _balon.portador_actual is Jugador3D:
		var portador: Jugador3D = _balon.portador_actual as Jugador3D
		nuevo_poseedor = int(portador.equipo)
		nuevo_ataque_local = (nuevo_poseedor == 0)
	else:
		# Si el balón está libre (ej. durante un pase), mantener ataque si el último toque fue local y hay un jugador local cercano
		var ultimo_eq: int = _balon.ultimo_toque_equipo
		nuevo_poseedor = ultimo_eq
		if ultimo_eq == 1:
			nuevo_ataque_local = false
		else:
			var activos: Array[Node] = get_tree().get_nodes_in_group("jugador_activo")
			if not activos.is_empty() and activos[0] is Jugador3D:
				var j_act: Jugador3D = activos[0] as Jugador3D
				nuevo_ataque_local = (j_act.global_position.distance_to(_balon.global_position) <= 4.2) or _balon._en_pase_hueco
			else:
				nuevo_ataque_local = true
	
	if forzar_emision or nuevo_ataque_local != _en_ataque_local_actual or nuevo_poseedor != _equipo_poseedor_actual:
		_en_ataque_local_actual = nuevo_ataque_local
		_equipo_poseedor_actual = nuevo_poseedor
		posesion_cambiada.emit(_en_ataque_local_actual, _equipo_poseedor_actual)


## Retorna true si el partido aguarda el pase obligatorio del saque de centro
func es_saque_centro_activo() -> bool:
	return estado == EstadoPartido.SAQUE_CENTRO


## Activa inmediatamente el estado EN_JUEGO y el reloj neto únicamente cuando el balón sale de los pies tras el pase inicial
func notificar_toque_saque_centro() -> void:
	if estado == EstadoPartido.SAQUE_CENTRO:
		_finalizar_reanudacion()


func _physics_process(delta: float) -> void:
	if GameManager:
		GameManager.reloj_neto_activo = (estado == EstadoPartido.EN_JUEGO)
	
	_actualizar_estado_posesion_hud(false)
	
	if estado == EstadoPartido.EN_JUEGO or estado == EstadoPartido.ENTRADA_EQUIPOS or estado == EstadoPartido.TIEMPO_MUERTO:
		cuenta_regresiva_4s_actualizada.emit(0.0, false)
		return
	
	if _balon == null:
		_conectar_balon()
		if _balon == null:
			return
	
	# Regla Futsal para Saque de Centro: traslación bloqueada en el centro;
	# el partido y el reloj neto solo se activan al soltar el balón mediante PASE o HUECO.
	if estado == EstadoPartido.SAQUE_CENTRO:
		cuenta_regresiva_4s_actualizada.emit(0.0, false)
		_aplicar_regla_circulo_central()
		if _sacador_actual and is_instance_valid(_sacador_actual):
			if not _sacador_actual._en_posicion_saque:
				_sacador_actual.fijar_en_saque(true, _sacador_actual._pos_anclaje_saque)
		return
	
	# Mantener al sacador plantado en su posición reglamentaria hasta que patee o lance con la mano
	if _esperando_toque and _sacador_actual and is_instance_valid(_sacador_actual):
		if not _sacador_actual._en_posicion_saque:
			_sacador_actual.fijar_en_saque(true, _sacador_actual._pos_anclaje_saque)
	
	# Aplicar continuamente la barrera reglamentaria (4m o pasillo libre en Doble Penalti)
	if estado == EstadoPartido.DOBLE_PENALTI:
		_mantener_despeje_doble_penalti()
	else:
		_aplicar_regla_4m(false)
	
	# Regla oficial de los 4 Segundos en reanudaciones (Banda, Meta, Esquina, Tiro Libre, Doble Penalti)
	if _esperando_toque and _timer_timeout > 0.0:
		_timer_timeout = maxf(0.0, _timer_timeout - delta)
		cuenta_regresiva_4s_actualizada.emit(_timer_timeout, true)
		if _timer_timeout <= 0.0 and not _sancionando_4s:
			_sancionar_regla_4_segundos()
	else:
		cuenta_regresiva_4s_actualizada.emit(0.0, false)


# ==============================================================================
# 1. SECUENCIA DE ENTRADA DESDE BANQUILLOS Y SAQUE DE CENTRO REGLAMENTARIO
# ==============================================================================

## Verifica y aplica los uniformes diferenciados a los 10 jugadores (RFC Rojo vs ASF Amarillo y arqueros contrastantes)
func _verificar_uniformes_equipos() -> void:
	var contenedor_jugs: Node = get_parent().get_node_or_null("Jugadores") if get_parent() else null
	if contenedor_jugs:
		for hijo: Node in contenedor_jugs.get_children():
			var jug: Jugador3D = hijo as Jugador3D
			if jug:
				if jug.name.begins_with("Vis_"):
					jug.aplicar_uniforme_equipo(1)
				elif jug.name.begins_with("Local_"):
					jug.aplicar_uniforme_equipo(0)
				else:
					jug.aplicar_uniforme_equipo(int(jug.equipo))
	else:
		var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
		for n: Node in todos:
			var jug: Jugador3D = n as Jugador3D
			if jug:
				jug.aplicar_uniforme_equipo(int(jug.equipo))


func iniciar_entrada_equipos() -> void:
	if _balon == null:
		_conectar_balon()
	
	_verificar_uniformes_equipos()
	_cambiar_estado(EstadoPartido.ENTRADA_EQUIPOS)
	_esperando_toque = false
	
	if _balon:
		_balon.colocar_en_reanudacion(Vector3(0.0, 0.25, 0.0))
		_balon.esta_fuera_de_juego = false
		_balon.sacador_autorizado = null
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var idx_loc: int = 0
	for n: Node in locales:
		var j_loc: Jugador3D = n as Jugador3D
		if j_loc:
			var pos_banquillo_loc: Vector3 = Vector3(-8.5 + float(idx_loc) * 1.1, 0.0, -11.4)
			j_loc.iniciar_entrada_cancha(pos_banquillo_loc)
			idx_loc += 1
	
	var visitantes: Array[Node] = get_tree().get_nodes_in_group("equipo_visitante")
	var idx_vis: int = 0
	for n: Node in visitantes:
		var j_vis: Jugador3D = n as Jugador3D
		if j_vis:
			var pos_banquillo_vis: Vector3 = Vector3(5.0 + float(idx_vis) * 1.1, 0.0, -11.4)
			j_vis.iniciar_entrada_cancha(pos_banquillo_vis)
			idx_vis += 1
	
	_emitir_anuncio_hud("¡SALEN LOS EQUIPOS A LA CANCHA!")
	await get_tree().create_timer(t_duracion_entrada).timeout
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j):
			j.finalizar_entrada_cancha()
	
	_emitir_anuncio_hud("¡PITAZO INICIAL!")
	iniciar_saque_centro(0)


## Configura el saque de centro reglamentario:
## - Sacador (#10 J. Álvarez / Pivot) a 0.5m del balón en el punto central con posesión asignada.
## - Compañero de ataque cerca del círculo central y rivales fuera del círculo central (respetando los 3m).
## - Control inmediato habilitado; el reloj neto de 20:00 inicia al impactar/jugar el balón.
func iniciar_saque_centro(equipo_sacador: int = 0) -> void:
	if _balon == null:
		_conectar_balon()
	
	_sancionando_4s = false
	_equipo_sacador = equipo_sacador
	_pos_saque = Vector3(0.0, 0.25, 0.0)
	_cambiar_estado(EstadoPartido.SAQUE_CENTRO)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j):
			j.fijar_en_saque(false)
			j.soltar_posesion()
			j.set_congelado(false)
			j.velocity = Vector3.ZERO
	
	var sacador: Jugador3D = _obtener_sacador_centro(equipo_sacador)
	_sacador_actual = sacador
	
	# Ubicar reglamentariamente a compañeros y rivales (todos los rivales fuera del círculo de 3 metros)
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j == null or not is_instance_valid(j) or j == sacador:
			continue
		
		var es_equipo_sacador: bool = (int(j.equipo) == equipo_sacador)
		var signo_campo: float = -1.0 if int(j.equipo) == 0 else 1.0
		
		if j.posicion_tactica == "PORTERO":
			j.global_position = Vector3(18.5 * signo_campo, 0.0, 0.0)
		elif j.posicion_tactica == "CIERRE":
			j.global_position = Vector3(11.5 * signo_campo, 0.0, 0.0)
		elif j.posicion_tactica == "ALA_IZQ":
			if es_equipo_sacador:
				# Compañero de ataque cerca del borde del círculo central listo para recibir el primer pase
				j.global_position = Vector3(0.8 * signo_campo, 0.0, -3.15)
			else:
				j.global_position = Vector3(6.0 * signo_campo, 0.0, -6.2)
		elif j.posicion_tactica == "ALA_DER":
			if es_equipo_sacador:
				j.global_position = Vector3(2.8 * signo_campo, 0.0, 3.25)
			else:
				j.global_position = Vector3(6.0 * signo_campo, 0.0, 6.2)
		elif j.posicion_tactica == "PIVOT":
			# El delantero rival debe ubicarse fuera del círculo central (> 3.0m)
			j.global_position = Vector3(3.6 * signo_campo, 0.0, 0.0)
		
		var dir_mirada: Vector3 = Vector3(-signo_campo, 0.0, 0.0)
		j.rotation.y = atan2(-dir_mirada.x, -dir_mirada.z)
		j.velocity = Vector3.ZERO
	
	if _balon:
		_balon.colocar_en_reanudacion(_pos_saque)
		_balon.sacador_autorizado = sacador
	
	if sacador != null:
		# Colocar al sacador a exactamente 0.5 metros del balón en el punto central
		var dir_ataque: Vector3 = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
		var pos_anclaje_centro: Vector3 = Vector3(-0.5 if equipo_sacador == 0 else 0.5, 0.0, 0.0)
		sacador.fijar_en_saque(true, pos_anclaje_centro)
		sacador.rotation.y = atan2(-dir_ataque.x, -dir_ataque.z)
		sacador.velocity = Vector3.ZERO
		sacador.set_congelado(false)
		
		if _balon:
			sacador.tomar_posesion(_balon)
			_balon.global_position = _pos_saque
			sacador._tiempo_inmunidad_robo = 4.0
		
		if equipo_sacador == 0:
			_asignar_control_exclusivo(sacador)
		else:
			sacador._cooldown_decision_ia = 0.55
	
	_aplicar_regla_circulo_central()
	_esperando_toque = true
	_timer_timeout = 0.0


## Mantiene a todos los rivales fuera del círculo central (radio >= 3.0m) durante el saque de centro
func _aplicar_regla_circulo_central() -> void:
	var grupo_rival: String = "equipo_visitante" if _equipo_sacador == 0 else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
	var radio_min: float = radio_circulo_central + 0.35
	
	for n: Node in rivales:
		var rival: Jugador3D = n as Jugador3D
		if rival == null or rival.posicion_tactica == "PORTERO":
			continue
		var pos_plana: Vector3 = Vector3(rival.global_position.x, 0.0, rival.global_position.z)
		var d: float = pos_plana.length()
		if d < radio_min:
			var dir_empuje: Vector3 = pos_plana.normalized() if d > 0.05 else Vector3(1.0 if _equipo_sacador == 0 else -1.0, 0.0, 0.0)
			var nueva_pos: Vector3 = dir_empuje * radio_min
			rival.global_position = Vector3(nueva_pos.x, 0.0, nueva_pos.z)
			rival.velocity = Vector3.ZERO


# ==============================================================================
# 2. REANUDACIONES REGLAMENTARIAS (BANDA CON PIE, META CON MANO, ESQUINA, TIRO LIBRE)
# ==============================================================================

func iniciar_reanudacion(tipo: EstadoPartido, pos: Vector3, equipo_sacador: int) -> void:
	if _balon == null:
		_conectar_balon()
	
	_sancionando_4s = false
	_equipo_sacador = equipo_sacador
	_pos_saque = pos
	_cambiar_estado(tipo)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j_limpio: Jugador3D = n as Jugador3D
		if j_limpio:
			j_limpio.fijar_en_saque(false)
			j_limpio.soltar_posesion()
	
	# Regla Oficial: En SAQUE_META saca el PORTERO con la mano desde dentro de su área;
	# en SAQUE_BANDA, SAQUE_ESQUINA y TIRO_LIBRE saca un jugador de campo con el pie detenido.
	var sacador: Jugador3D = null
	if tipo == EstadoPartido.SAQUE_META:
		sacador = _obtener_portero(equipo_sacador)
		var x_area_meta: float = -18.2 if equipo_sacador == 0 else 18.2
		_pos_saque = Vector3(x_area_meta, 0.25, clampf(pos.z, -1.2, 1.2))
	else:
		sacador = _obtener_sacador_campo(_pos_saque, equipo_sacador)
	
	_sacador_actual = sacador
	
	if _balon:
		_balon.colocar_en_reanudacion(_pos_saque)
		_balon.sacador_autorizado = sacador
	
	if sacador != null:
		var dir_hacia_campo: Vector3 = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
		var pos_anclaje: Vector3 = _pos_saque
		
		if tipo == EstadoPartido.SAQUE_BANDA:
			# Saque de banda estrictamente detenido con el pie sobre la línea de banda
			dir_hacia_campo = Vector3(0.0, 0.0, -1.0 if _pos_saque.z > 0.0 else 1.0)
			var z_linea: float = 9.98 if _pos_saque.z > 0.0 else -9.98
			_pos_saque = Vector3(clampf(_pos_saque.x, -18.8, 18.8), 0.22, z_linea)
			if _balon:
				_balon.global_position = _pos_saque
			pos_anclaje = Vector3(_pos_saque.x, 0.0, z_linea + (0.28 if z_linea > 0.0 else -0.28))
		elif tipo == EstadoPartido.SAQUE_ESQUINA:
			dir_hacia_campo = Vector3(-signf(_pos_saque.x), 0.0, -signf(_pos_saque.z)).normalized()
			pos_anclaje = _pos_saque - dir_hacia_campo * 0.52
		elif tipo == EstadoPartido.SAQUE_META:
			dir_hacia_campo = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
			pos_anclaje = Vector3(_pos_saque.x, 0.0, _pos_saque.z)
		else:
			pos_anclaje = _pos_saque - dir_hacia_campo * 0.62
		
		pos_anclaje.y = 0.0
		sacador.fijar_en_saque(true, pos_anclaje)
		sacador.rotation.y = atan2(-dir_hacia_campo.x, -dir_hacia_campo.z)
		sacador.velocity = Vector3.ZERO
		
		if _balon:
			if tipo == EstadoPartido.SAQUE_META:
				# El portero reanuda únicamente con la mano desde dentro del área
				sacador.atrapar_con_manos(_balon)
			else:
				sacador.tomar_posesion(_balon)
			sacador._tiempo_inmunidad_robo = t_timeout_saque + 1.5
		
		if equipo_sacador == 0:
			_asignar_control_exclusivo(sacador)
		else:
			sacador._cooldown_decision_ia = t_pausa_saque + 0.35
	
	# Congelar brevemente al resto durante la colocación del saque
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			if j == sacador:
				j.set_congelado(false)
			else:
				j.set_congelado(true)
				j.velocity = Vector3.ZERO
	
	_esperando_toque = true
	_timer_timeout = t_timeout_saque
	_aplicar_regla_4m(true)
	
	await get_tree().create_timer(t_pausa_saque).timeout
	
	if estado == tipo:
		for n: Node in todos:
			var j: Jugador3D = n as Jugador3D
			if j and is_instance_valid(j):
				j.set_congelado(false)


# ==============================================================================
# 3. ACUMULACIÓN DE FALTAS Y DOBLE PENALTI A 10 METROS (6ª FALTA SIN BARRERA)
# ==============================================================================

func registrar_falta(equipo_infractor: int, pos_falta: Vector3) -> void:
	if estado != EstadoPartido.EN_JUEGO:
		return
	
	var total_faltas: int = 1
	if GameManager:
		total_faltas = GameManager.registrar_falta_equipo(equipo_infractor)
	
	var equipo_favorecido: int = 1 if equipo_infractor == 0 else 0
	
	# A partir de la 6ª falta acumulada en el mismo periodo: Doble Penalti desde 10m sin barrera
	if total_faltas >= 6:
		iniciar_doble_penalti(equipo_favorecido, total_faltas)
	else:
		_emitir_anuncio_hud("¡FALTA! (%d/5 ACUMULADAS) - TIRO LIBRE" % total_faltas)
		var pos_tl: Vector3 = Vector3(clampf(pos_falta.x, -13.5, 13.5), 0.25, clampf(pos_falta.z, -8.5, 8.5))
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, pos_tl, equipo_favorecido)


func iniciar_doble_penalti(equipo_ejecutor: int, num_falta: int = 6) -> void:
	if _balon == null:
		_conectar_balon()
	
	_sancionando_4s = false
	_equipo_sacador = equipo_ejecutor
	_cambiar_estado(EstadoPartido.DOBLE_PENALTI)
	
	# Segundo punto penal reglamentario: a 10 metros de la línea de meta (±10.0m en cancha de ±20.0m)
	var x_segundo_penal: float = 10.0 if equipo_ejecutor == 0 else -10.0
	_pos_saque = Vector3(x_segundo_penal, 0.25, 0.0)
	
	_emitir_anuncio_hud("¡%dª FALTA! ¡DOBLE PENALTI A 10M SIN BARRERA!" % num_falta)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j_limpio: Jugador3D = n as Jugador3D
		if j_limpio:
			j_limpio.fijar_en_saque(false)
			j_limpio.soltar_posesion()
	
	var ejecutor: Jugador3D = _obtener_sacador_centro(equipo_ejecutor)
	var portero_rival: Jugador3D = _obtener_portero(1 if equipo_ejecutor == 0 else 0)
	_sacador_actual = ejecutor
	
	if _balon:
		_balon.colocar_en_reanudacion(_pos_saque)
		_balon.sacador_autorizado = ejecutor
	
	# Despejar a todos los demás jugadores detrás de la línea del balón (prohibida la barrera)
	_mantener_despeje_doble_penalti()
	
	# Posicionar al portero defensor a mínimo 5m del balón (sobre su línea de meta)
	if portero_rival:
		var x_meta_rival: float = 19.3 if equipo_ejecutor == 0 else -19.3
		portero_rival.global_position = Vector3(x_meta_rival, 0.0, 0.0)
		portero_rival.velocity = Vector3.ZERO
	
	if ejecutor:
		var dir_arco: Vector3 = Vector3(1.0 if equipo_ejecutor == 0 else -1.0, 0.0, 0.0)
		var pos_anclaje: Vector3 = _pos_saque - dir_arco * 0.65
		pos_anclaje.y = 0.0
		ejecutor.fijar_en_saque(true, pos_anclaje)
		ejecutor.rotation.y = atan2(-dir_arco.x, -dir_arco.z)
		ejecutor.velocity = Vector3.ZERO
		if _balon:
			ejecutor.tomar_posesion(_balon)
			ejecutor._tiempo_inmunidad_robo = t_timeout_saque + 2.0
		
		if equipo_ejecutor == 0:
			_asignar_control_exclusivo(ejecutor)
		else:
			ejecutor._cooldown_decision_ia = 1.15
	
	_esperando_toque = true
	_timer_timeout = t_timeout_saque


func _mantener_despeje_doble_penalti() -> void:
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	var idx_fila: int = 0
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j == null or j == _sacador_actual or j.posicion_tactica == "PORTERO":
			continue
		# Todos los jugadores de campo deben permanecer detrás de la línea del balón y a más de 5m
		var x_detras: float = 4.0 if _equipo_sacador == 0 else -4.0
		var z_lateral: float = -7.5 + float(idx_fila % 4) * 5.0
		if (_equipo_sacador == 0 and j.global_position.x > 5.5) or (_equipo_sacador == 1 and j.global_position.x < -5.5):
			j.global_position = Vector3(x_detras, 0.0, z_lateral)
			j.velocity = Vector3.ZERO
		idx_fila += 1


# ==============================================================================
# 4. REGLA DE LOS 4 SEGUNDOS (PÉRDIDA DE POSESIÓN POR DEMORA EN EL SAQUE)
# ==============================================================================

func _sancionar_regla_4_segundos() -> void:
	if not _esperando_toque or _sancionando_4s:
		return
	
	_sancionando_4s = true
	_esperando_toque = false
	var estado_previo: EstadoPartido = estado
	var equipo_infractor: int = _equipo_sacador
	var equipo_beneficiado: int = 1 if equipo_infractor == 0 else 0
	var pos_anterior: Vector3 = _pos_saque
	
	if _sacador_actual and is_instance_valid(_sacador_actual):
		_sacador_actual.fijar_en_saque(false)
		_sacador_actual.soltar_posesion()
	
	if estado_previo == EstadoPartido.SAQUE_META:
		# Si el portero demora más de 4s: tiro libre indirecto para el rival al borde del área de 6m
		_emitir_anuncio_hud("¡4 SEGUNDOS DEL PORTERO! TIRO LIBRE RIVAL")
		var x_borde_area: float = -13.8 if equipo_infractor == 0 else 13.8
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, Vector3(x_borde_area, 0.25, 0.0), equipo_beneficiado)
	else:
		# En saque de banda, córner o tiro libre: la posesión pasa al equipo contrario
		_emitir_anuncio_hud("¡REGLA DE 4 SEGUNDOS! POSESIÓN RIVAL")
		var z_banda: float = 9.95 if pos_anterior.z >= 0.0 else -9.95
		iniciar_reanudacion(EstadoPartido.SAQUE_BANDA, Vector3(clampf(pos_anterior.x, -18.5, 18.5), 0.25, z_banda), equipo_beneficiado)


# ==============================================================================
# 5. BOTÓN DE TIEMPO MUERTO (1 MINUTO TÁCTICO POR TIEMPO CON POSESIÓN)
# ==============================================================================

func equipo_posee_balon(equipo_consulta: int) -> bool:
	if _balon == null:
		return false
	if estado != EstadoPartido.EN_JUEGO and _esperando_toque:
		return _equipo_sacador == equipo_consulta
	if _balon.esta_siendo_conducido() and _balon.portador_actual is Jugador3D:
		var portador: Jugador3D = _balon.portador_actual as Jugador3D
		return int(portador.equipo) == equipo_consulta
	return false


func solicitar_tiempo_muerto(equipo_solicitante: int = 0) -> bool:
	if GameManager == null or not GameManager.puede_pedir_tiempo_muerto(equipo_solicitante):
		_emitir_anuncio_hud("TIEMPO MUERTO YA UTILIZADO EN ESTE PERIODO")
		return false
	
	if estado == EstadoPartido.TIEMPO_MUERTO or estado == EstadoPartido.ENTRADA_EQUIPOS or estado == EstadoPartido.GOL:
		return false
	
	if not equipo_posee_balon(equipo_solicitante):
		_emitir_anuncio_hud("DEBES TENER LA POSESIÓN PARA PEDIR TIEMPO MUERTO")
		return false
	
	GameManager.usar_tiempo_muerto(equipo_solicitante)
	_ejecutar_pausa_tiempo_muerto(equipo_solicitante)
	return true


func _ejecutar_pausa_tiempo_muerto(equipo_solicitante: int) -> void:
	var estado_anterior: EstadoPartido = estado
	_cambiar_estado(EstadoPartido.TIEMPO_MUERTO)
	
	var nombre_eq: String = "LOCAL" if equipo_solicitante == 0 else "VISITANTE"
	_emitir_anuncio_hud("⏱ ¡TIEMPO MUERTO %s! (PAUSA TÁCTICA)" % nombre_eq)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			j.set_congelado(true)
			j.velocity = Vector3.ZERO
	
	await get_tree().create_timer(t_duracion_tiempo_muerto).timeout
	
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j):
			j.set_congelado(false)
	
	_emitir_anuncio_hud("¡SE REANUDA EL PARTIDO!")
	if estado_anterior != EstadoPartido.EN_JUEGO and _esperando_toque:
		_timer_timeout = t_timeout_saque
		_cambiar_estado(estado_anterior)
	else:
		_cambiar_estado(EstadoPartido.EN_JUEGO)


# ==============================================================================
# 6. CAMBIO DE PERIODO (FIN DEL 1ER TIEMPO -> 2DO TIEMPO) Y GOL
# ==============================================================================

func _on_fin_primer_tiempo() -> void:
	_esperando_toque = false
	_cambiar_estado(EstadoPartido.TIEMPO_MUERTO)
	_emitir_anuncio_hud("¡FIN DEL 1ER TIEMPO! FALTAS REINICIADAS")
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			j.fijar_en_saque(false)
			j.soltar_posesion()
			j.set_congelado(true)
			j.velocity = Vector3.ZERO
	
	await get_tree().create_timer(2.2).timeout
	
	if GameManager:
		GameManager.iniciar_segundo_tiempo()
	
	_emitir_anuncio_hud("¡PITAZO INICIAL! 2DO TIEMPO")
	iniciar_saque_centro(1)


## Gestiona la celebración del gol y el saque desde el centro del campo
func iniciar_gol(equipo_que_anoto: int) -> void:
	if _balon == null:
		_conectar_balon()
	
	_cambiar_estado(EstadoPartido.GOL)
	_esperando_toque = false
	
	if _balon:
		_balon.esta_fuera_de_juego = true
		_balon.detener()
	
	# 1. Congelar a todos los jugadores durante la celebración del gol
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			j.fijar_en_saque(false)
			j.set_congelado(true)
			j.velocity = Vector3.ZERO
	
	await get_tree().create_timer(t_celebracion_gol).timeout
	
	# 2. Reanudar con saque de centro reglamentario para el equipo que recibió el gol
	var equipo_receptor_gol: int = 1 if equipo_que_anoto == 0 else 0
	iniciar_saque_centro(equipo_receptor_gol)


## Callback cuando el balón es pateado o lanzado por el sacador
func _on_balon_liberado() -> void:
	_finalizar_reanudacion()


## Finaliza la reanudación pasando al estado EN_JUEGO y activando el reloj neto
func _finalizar_reanudacion() -> void:
	if _esperando_toque or (estado != EstadoPartido.EN_JUEGO and estado != EstadoPartido.ENTRADA_EQUIPOS and estado != EstadoPartido.TIEMPO_MUERTO):
		_esperando_toque = false
		cuenta_regresiva_4s_actualizada.emit(0.0, false)
		if _balon:
			_balon.sacador_autorizado = null
		
		if _sacador_actual and is_instance_valid(_sacador_actual):
			_sacador_actual.fijar_en_saque(false)
			_sacador_actual._tiempo_inmunidad_robo = 1.2
		
		var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
		for n: Node in todos:
			var j: Jugador3D = n as Jugador3D
			if j and is_instance_valid(j):
				j.fijar_en_saque(false)
				if j._congelado:
					j.set_congelado(false)
		
		_sacador_actual = null
		_cambiar_estado(EstadoPartido.EN_JUEGO)


## Aplica la barrera reglamentaria de 4 metros a todos los rivales del equipo sacador
func _aplicar_regla_4m(reubicacion_inicial: bool = false) -> void:
	if _balon == null:
		return
	
	var pos_b: Vector3 = _pos_saque
	var grupo_rival: String = "equipo_visitante" if _equipo_sacador == 0 else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
	
	var R: float = distancia_reglamentaria + margen_distancia
	
	for nodo: Node in rivales:
		var rival: Jugador3D = nodo as Jugador3D
		if rival == null or rival.posicion_tactica == "PORTERO":
			continue
		
		var pos_r: Vector3 = rival.global_position
		var diff: Vector3 = pos_r - pos_b
		diff.y = 0.0
		var d: float = diff.length()
		
		var viola_distancia: bool = (d < distancia_reglamentaria)
		var viola_area_meta: bool = false
		
		# En SAQUE_META el rival tampoco puede estar dentro del área de 6m (|x| > 14 del lado del sacador)
		if estado == EstadoPartido.SAQUE_META:
			if _equipo_sacador == 0 and pos_r.x < -14.0:
				viola_area_meta = true
			elif _equipo_sacador == 1 and pos_r.x > 14.0:
				viola_area_meta = true
		
		if viola_distancia or viola_area_meta:
			if not reubicacion_inicial and d > 0.25 and not viola_area_meta:
				var dir_radial: Vector3 = diff.normalized()
				var nueva_pos: Vector3 = pos_b + dir_radial * (distancia_reglamentaria + 0.06)
				nueva_pos.x = clampf(nueva_pos.x, -19.2, 19.2)
				nueva_pos.z = clampf(nueva_pos.z, -9.5, 9.5)
				rival.global_position = Vector3(nueva_pos.x, 0.0, nueva_pos.z)
				var vel_radial: float = rival.velocity.dot(dir_radial)
				if vel_radial < 0.0:
					rival.velocity -= dir_radial * vel_radial
				continue
			
			var angulo_base: float = atan2(diff.z, diff.x)
			if diff.length_squared() < 0.001:
				angulo_base = 0.0 if _equipo_sacador == 0 else PI
			
			var indices_ordenados: Array[int] = [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8]
			var paso_angular: float = TAU / 16.0
			
			var pos_reubicada: Vector3 = Vector3.ZERO
			var posicion_encontrada: bool = false
			
			for idx: int in indices_ordenados:
				var ang: float = angulo_base + (float(idx) * paso_angular)
				var cand_x: float = pos_b.x + cos(ang) * R
				var cand_z: float = pos_b.z + sin(ang) * R
				
				if abs(cand_x) <= 19.0 and abs(cand_z) <= 9.5:
					if estado == EstadoPartido.SAQUE_META:
						if _equipo_sacador == 0 and cand_x < -14.0:
							continue
						elif _equipo_sacador == 1 and cand_x > 14.0:
							continue
					
					pos_reubicada = Vector3(cand_x, 0.0, cand_z)
					posicion_encontrada = true
					break
			
			if not posicion_encontrada:
				var fallback_x: float = clampf(pos_b.x + cos(angulo_base) * R, -19.0, 19.0)
				var fallback_z: float = clampf(pos_b.z + sin(angulo_base) * R, -9.5, 9.5)
				if estado == EstadoPartido.SAQUE_META:
					if _equipo_sacador == 0 and fallback_x < -14.0:
						fallback_x = -13.5
					elif _equipo_sacador == 1 and fallback_x > 14.0:
						fallback_x = 13.5
				pos_reubicada = Vector3(fallback_x, 0.0, fallback_z)
				posicion_encontrada = true
			
			if posicion_encontrada:
				rival.global_position = pos_reubicada
				rival.velocity = Vector3.ZERO


func _obtener_portero(equipo_sac: int) -> Jugador3D:
	var grupo: String = "equipo_local" if equipo_sac == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	for n: Node in jugadores:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug.posicion_tactica == "PORTERO":
			return jug
	return _obtener_sacador_campo(_pos_saque, equipo_sac)


func _obtener_companero_mas_cercano(sacador: Jugador3D) -> Jugador3D:
	var grupo: String = "equipo_local" if _equipo_sacador == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	for n: Node in jugadores:
		var j: Jugador3D = n as Jugador3D
		if j and j != sacador and j.posicion_tactica != "PORTERO":
			var d: float = 999.0
			if sacador != null:
				d = sacador.global_position.distance_to(j.global_position)
			elif _balon != null:
				d = _balon.global_position.distance_to(j.global_position)
			if d < min_dist:
				min_dist = d
				mas_cercano = j
	return mas_cercano


func _obtener_sacador_campo(pos_balon: Vector3, equipo_sac: int) -> Jugador3D:
	var grupo: String = "equipo_local" if equipo_sac == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	
	for n: Node in jugadores:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug.posicion_tactica != "PORTERO":
			var d: float = jug.global_position.distance_to(pos_balon)
			if d < min_dist:
				min_dist = d
				mas_cercano = jug
	
	return mas_cercano


func _obtener_sacador_centro(equipo_sac: int) -> Jugador3D:
	var grupo: String = "equipo_local" if equipo_sac == 0 else "equipo_visitante"
	var jugadores: Array[Node] = get_tree().get_nodes_in_group(grupo)
	
	for n: Node in jugadores:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug.posicion_tactica == "PIVOT":
			return jug
	
	return _obtener_sacador_campo(Vector3.ZERO, equipo_sac)


func _asignar_control_exclusivo(jugador_a_controlar: Jugador3D) -> void:
	if jugador_a_controlar == null:
		return
	jugador_a_controlar._asignar_control_a_este_jugador()


func _emitir_anuncio_hud(texto: String) -> void:
	var hud: HUDPartido = get_tree().get_first_node_in_group("hud_partido") as HUDPartido
	if hud and is_instance_valid(hud):
		hud.mostrar_anuncio(texto)

