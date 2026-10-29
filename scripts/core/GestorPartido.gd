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
	GOL,
	## Estado pasivo del modo Entrenamiento: el gestor solo publica la posesión (HUD Ataque/Defensa)
	## y no aplica entrada de equipos, reloj, regla de 4 s, 5 m ni faltas (las gestiona el wrapper de entrenamiento).
	ENTRENAMIENTO
}

signal estado_cambiado(nuevo: EstadoPartido)
signal cuenta_regresiva_4s_actualizada(segundos_restantes: float, activa: bool)
signal sancion_2min_actualizada(equipo_sancionado: int, segundos_restantes: float, activa: bool)
signal tarjeta_mostrada(jugador: Jugador3D, tipo_tarjeta: String, puntaje_severidad: float)
signal gol_anotado(equipo_anotador: int)
signal posesion_cambiada(en_ataque_local: bool, equipo_poseedor: int)

@export var distancia_reglamentaria: float = 5.0
@export var distancia_barrera_futsal: float = 5.0
@export var radio_circulo_central: float = 3.0
@export var margen_distancia: float = 0.3
@export var t_pausa_saque: float = 0.65
@export var t_celebracion_gol: float = 2.0
@export var t_timeout_saque: float = 4.0
@export var t_duracion_entrada: float = 2.4
@export var t_duracion_tiempo_muerto: float = 3.5
## Modo Entrenamiento: el gestor queda en estado pasivo `ENTRENAMIENTO` y solo mantiene la posesión para el HUD.
@export var modo_entrenamiento: bool = false

## Reglas FIFA/IFAB de Tiro Directo vs. Indirecto y Doble Toque
var es_tiro_indirecto: bool = false
var toques_en_jugada: int = 0

var _defensores_barrera_tl: Array[Jugador3D] = []
var _posiciones_barrera_tl: Array[Vector3] = []

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
var _reproductor_silbato: AudioStreamPlayer = null

## Control de Sanciones Disciplinarias y Expulsiones (FIFA/IFAB Ley 12 - Regla de los 2 Minutos)
var tiempo_inferioridad_local: float = 0.0
var inferioridad_local_activa: bool = false
var jugador_expulsado_local: Jugador3D = null

var tiempo_inferioridad_visitante: float = 0.0
var inferioridad_visitante_activa: bool = false
var jugador_expulsado_visitante: Jugador3D = null

## Control de Cinemática de Faltas, Repetición Ligera y Ventana Pre-Pitazo (Estilo eFootball / FC Mobile)
const ReplayBufferClass = preload("res://scripts/core/ReplayBuffer.gd")
const FiguraArbitro3DClass = preload("res://scripts/visual/FiguraArbitro3D.gd")

var esperando_pitazo_arbitro: bool = false
var _en_cinematica_falta: bool = false
var _tween_cinematica: Tween = null
var _figura_arbitro_instancia: Node3D = null
var _replay_buffer = null
var _datos_falta_pendiente: Dictionary = {}
var _camara_referencia: CamaraTransmision = null


func _ready() -> void:
	add_to_group("gestor_partido")
	_replay_buffer = ReplayBufferClass.new()
	_inicializar_silbato_arbitral()
	_conectar_balon()
	if not gol_anotado.is_connected(_on_gol_anotado):
		gol_anotado.connect(_on_gol_anotado)
	if GameManager and not GameManager.fin_primer_tiempo.is_connected(_on_fin_primer_tiempo):
		GameManager.fin_primer_tiempo.connect(_on_fin_primer_tiempo)
	if modo_entrenamiento:
		estado = EstadoPartido.ENTRENAMIENTO
		return
	call_deferred("iniciar_entrada_equipos")


func _inicializar_silbato_arbitral() -> void:
	_reproductor_silbato = AudioStreamPlayer.new()
	_reproductor_silbato.name = "SilbatoArbitral"
	_reproductor_silbato.volume_db = -5.0
	add_child(_reproductor_silbato)
	var sample_rate: int = 22050
	var duracion: float = 0.42
	var total_muestras: int = int(sample_rate * duracion)
	var datos_pcm: PackedByteArray = PackedByteArray()
	datos_pcm.resize(total_muestras * 2)
	for i: int in range(total_muestras):
		var t: float = float(i) / float(sample_rate)
		var env: float = clampf(t / 0.02, 0.0, 1.0) * clampf((duracion - t) / 0.06, 0.0, 1.0)
		var mod_trino: float = 1.0 + 0.04 * sin(TAU * 28.0 * t)
		var onda: float = (sin(TAU * 2850.0 * mod_trino * t) * 0.65 + sin(TAU * 5700.0 * mod_trino * t) * 0.25) * env
		var muestra_i16: int = clampi(int(onda * 24000.0), -32767, 32767)
		datos_pcm.encode_s16(i * 2, muestra_i16)
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = datos_pcm
	_reproductor_silbato.stream = wav


func _reproducir_pitido_arbitral() -> void:
	if _reproductor_silbato and is_instance_valid(_reproductor_silbato):
		_reproductor_silbato.play()


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
	if modo_entrenamiento:
		return true
	return _en_ataque_local_actual


## Retorna true si hay un tiro libre o doble penalti en curso
func es_tiro_libre_activo() -> bool:
	return estado == EstadoPartido.TIRO_LIBRE or estado == EstadoPartido.DOBLE_PENALTI


## Retorna el equipo ejecutor de la reanudación actual (0: Local, 1: Visitante)
func obtener_equipo_sacador() -> int:
	return _equipo_sacador


## Retorna la posición del balón fijada para la reanudación actual
func obtener_pos_saque() -> Vector3:
	return _pos_saque


## Retorna el jugador que ejecuta la reanudación
func obtener_sacador_actual() -> Jugador3D:
	return _sacador_actual


## Retorna la referencia al balón de juego
func obtener_balon() -> Balon3D:
	return _balon


## Evalúa en tiempo real si el equipo local está en fase ofensiva (Ataque) o defensiva (Sin Balón) y emite señal al HUD
func _actualizar_estado_posesion_hud(forzar_emision: bool = false) -> void:
	if _balon == null:
		return
	
	var nuevo_ataque_local: bool = _en_ataque_local_actual
	var nuevo_poseedor: int = _equipo_poseedor_actual
	
	if modo_entrenamiento:
		nuevo_ataque_local = true
		nuevo_poseedor = 0
	elif estado != EstadoPartido.EN_JUEGO and _esperando_toque:
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
		elif estado == EstadoPartido.ENTRENAMIENTO:
			# Entrenamiento: tras patear/rebotar la iniciativa sigue siendo local (HUD de Ataque) hasta que un rival controle el balón
			nuevo_ataque_local = true
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
		GameManager.reloj_neto_activo = (estado == EstadoPartido.EN_JUEGO and not esperando_pitazo_arbitro and not _en_cinematica_falta)
	
	# Guardián de cámara: en juego vivo o saque de arquero (SAQUE_META), forzar que la cámara principal esté activa
	if estado == EstadoPartido.EN_JUEGO or estado == EstadoPartido.SAQUE_META:
		var cam_guard: CamaraTransmision = _obtener_camara_transmision()
		if cam_guard != null and is_instance_valid(cam_guard):
			if not cam_guard.is_current():
				cam_guard.make_current()
			if cam_guard.modo_camara == CamaraTransmision.ModoCamara.CINEMATICA_FALTA or cam_guard.modo_camara == CamaraTransmision.ModoCamara.REPETICION_JUGADA:
				cam_guard.regresar_a_broadcast(0.5)
	
	if _balon != null and is_instance_valid(_balon):
		es_tiro_indirecto = _balon.es_tiro_indirecto
		toques_en_jugada = _balon.toques_en_jugada
	
	_actualizar_estado_posesion_hud(false)
	if estado == EstadoPartido.ENTRENAMIENTO:
		# Wrapper de entrenamiento: sin sanciones, 4 s ni distancias reglamentarias
		return
	_actualizar_sanciones_2min(delta)

	# Grabar en Ring Buffer de repetición ligera durante juego en vivo
	if estado == EstadoPartido.EN_JUEGO and not esperando_pitazo_arbitro and not _en_cinematica_falta:
		if _replay_buffer and _balon:
			_replay_buffer.registrar_frame(delta, _balon, get_tree().get_nodes_in_group("jugadores_futsal"))
	
	if estado == EstadoPartido.EN_JUEGO or estado == EstadoPartido.ENTRADA_EQUIPOS or estado == EstadoPartido.TIEMPO_MUERTO:
		cuenta_regresiva_4s_actualizada.emit(0.0, false)
		if estado == EstadoPartido.EN_JUEGO and _balon and not _balon.esta_fuera_de_juego:
			var pos_b: Vector3 = _balon.global_position
			if absf(pos_b.x) >= 20.05:
				var dentro_marco: bool = (absf(pos_b.z) <= 1.52 and pos_b.y <= 2.02 and pos_b.y >= -0.05)
				if not dentro_marco:
					_balon.esta_fuera_de_juego = true
					_procesar_balon_fuera_linea_fondo(pos_b)
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
	
	# Aplicar continuamente la distancia reglamentaria de 5.0 metros en balón parado
	if estado == EstadoPartido.DOBLE_PENALTI:
		_mantener_despeje_doble_penalti()
	elif estado == EstadoPartido.TIRO_LIBRE:
		_mantener_barrera_tiro_libre()
	else:
		_aplicar_regla_5m(false)
	
	# Regla oficial de los 4 Segundos en reanudaciones (Banda, Meta, Esquina, Tiro Libre, Doble Penalti)
	if _esperando_toque and not esperando_pitazo_arbitro and _timer_timeout > 0.0:
		_timer_timeout = maxf(0.0, _timer_timeout - delta)
		cuenta_regresiva_4s_actualizada.emit(_timer_timeout, true)
		if _timer_timeout <= 0.0 and not _sancionando_4s:
			_sancionar_regla_4_segundos()
	elif esperando_pitazo_arbitro:
		# Durante la fase pre-pitazo (1.3 s de reconocimiento), el reloj reglamentario de 4s está pausado en 4.0s
		cuenta_regresiva_4s_actualizada.emit(4.0, false)
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
		if es_equipo_sacador and (j.posicion_tactica == "ALA_IZQ" or j.posicion_tactica == "ALA_DER"):
			var hacia_centro: Vector3 = _pos_saque - j.global_position
			hacia_centro.y = 0.0
			if hacia_centro.length_squared() > 0.01:
				dir_mirada = hacia_centro.normalized()
		j.rotation.y = atan2(-dir_mirada.x, -dir_mirada.z)
		j.velocity = Vector3.ZERO
	
	es_tiro_indirecto = false
	toques_en_jugada = 0
	if _balon:
		_balon.configurar_saque_reglamentario(_pos_saque, sacador, false)
	
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

func iniciar_reanudacion(tipo: EstadoPartido, pos: Vector3, equipo_sacador: int, tiro_indirecto: bool = false) -> void:
	if _balon == null:
		_conectar_balon()
	
	_sancionando_4s = false
	_equipo_sacador = equipo_sacador
	_pos_saque = pos
	# Según Reglas FIFA/IFAB de Futsal: Saque de banda y Saque de meta no pueden ser gol directo (1 toque)
	es_tiro_indirecto = tiro_indirecto or tipo == EstadoPartido.SAQUE_BANDA or tipo == EstadoPartido.SAQUE_META
	toques_en_jugada = 0
	_cambiar_estado(tipo)
	
	# En reanudaciones regulares (banda, meta, centro, esquina), garantizar cámara broadcast principal
	if tipo != EstadoPartido.TIRO_LIBRE and tipo != EstadoPartido.DOBLE_PENALTI:
		var cam_rean: CamaraTransmision = _obtener_camara_transmision()
		if cam_rean != null and is_instance_valid(cam_rean):
			cam_rean.regresar_a_broadcast(0.75)
			cam_rean.make_current()
			cam_rean.aplicar_lod_bias_personajes(1.0)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j_limpio: Jugador3D = n as Jugador3D
		if j_limpio:
			j_limpio.establecer_pose_barrera(false)
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
		_balon.configurar_saque_reglamentario(_pos_saque, sacador, es_tiro_indirecto)
	
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
		elif tipo == EstadoPartido.TIRO_LIBRE:
			var pos_arco_rival: Vector3 = Vector3(20.0 if equipo_sacador == 0 else -20.0, 0.0, 0.0)
			dir_hacia_campo = Vector3(pos_arco_rival.x - _pos_saque.x, 0.0, pos_arco_rival.z - _pos_saque.z).normalized()
			if dir_hacia_campo.length_squared() < 0.01:
				dir_hacia_campo = Vector3(1.0 if equipo_sacador == 0 else -1.0, 0.0, 0.0)
			var vec_derecha_tl: Vector3 = Vector3(-dir_hacia_campo.z, 0.0, dir_hacia_campo.x).normalized()
			pos_anclaje = _pos_saque - dir_hacia_campo * 1.45 - vec_derecha_tl * 0.48
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
	if tipo == EstadoPartido.TIRO_LIBRE:
		_configurar_barrera_y_posicionamiento_tiro_libre(equipo_sacador, _pos_saque)
	else:
		_aplicar_regla_5m(true)
	
	await get_tree().create_timer(t_pausa_saque).timeout
	
	if estado == tipo:
		for n: Node in todos:
			var j: Jugador3D = n as Jugador3D
			if j and is_instance_valid(j):
				j.set_congelado(false)


# ==============================================================================
# 3. ACUMULACIÓN DE FALTAS, ARBITRAJE ALGORÍTMICO Y SANCIONES DISCIPLINARIAS
# ==============================================================================

## Evalúa algorítmicamente la severidad de una falta (FIFA/IFAB Law 12):
## - Ángulo de entrada: si el infractor viene por la espalda del poseedor (dot < -0.3): +3.0 pts
## - Velocidad relativa: supera el 70% de su sprint máximo al momento del impacto: +2.0 pts
## - Ocasión manifiesta / Último defensor (DOGSO): 0 defensores de campo entre balón y arco rival: +2.5 pts
## - Fuerza excesiva / Barrida deslizante sin tocar balón: +2.0 pts
func evaluar_severidad_falta(infractor: Jugador3D, poseedor: Jugador3D, pos_falta: Vector3, es_barrida: bool) -> Dictionary:
	var puntaje: float = 0.0
	var desglose: Array[String] = []
	
	# 1. Ángulo de Entrada: aproximación por la espalda del portador (dot < -0.3)
	if poseedor and infractor:
		var facing_poseedor: Vector3 = -poseedor.global_transform.basis.z
		facing_poseedor.y = 0.0
		if facing_poseedor.length_squared() > 0.001:
			facing_poseedor = facing_poseedor.normalized()
		
		var dir_hacia_infractor: Vector3 = infractor.global_position - poseedor.global_position
		dir_hacia_infractor.y = 0.0
		if dir_hacia_infractor.length_squared() > 0.001:
			dir_hacia_infractor = dir_hacia_infractor.normalized()
			var dot_entrada: float = facing_poseedor.dot(dir_hacia_infractor)
			if dot_entrada < -0.3:
				puntaje += 3.0
				desglose.append("Entrada por detrás (+3.0)")
	
	# 2. Velocidad Relativa: supera el 70% de su sprint máximo
	if infractor:
		var vel_sprint_max: float = infractor.obtener_velocidad_sprint_max()
		if infractor.velocity.length() > vel_sprint_max * 0.70:
			puntaje += 2.0
			desglose.append("Velocidad de sprint excesiva (+2.0)")
	
	# 3. Ocasión Manifiesta / Último Defensor (DOGSO):
	# Si no hay ningún defensor de campo rival entre el balón y la línea de arco (solo el portero)
	if poseedor:
		var equipo_poseedor: int = int(poseedor.equipo)
		var x_arco_rival: float = 20.0 if equipo_poseedor == 0 else -20.0
		var pos_ref_x: float = pos_falta.x
		var grupo_defensa: String = "equipo_visitante" if equipo_poseedor == 0 else "equipo_local"
		var defensores_campo_intermedios: int = 0
		
		for n: Node in get_tree().get_nodes_in_group(grupo_defensa):
			var def_j: Jugador3D = n as Jugador3D
			if def_j and is_instance_valid(def_j) and not def_j.esta_expulsado and def_j != infractor:
				if def_j.posicion_tactica != "PORTERO":
					var def_x: float = def_j.global_position.x
					if (equipo_poseedor == 0 and def_x > pos_ref_x and def_x < x_arco_rival) or \
					   (equipo_poseedor == 1 and def_x < pos_ref_x and def_x > x_arco_rival):
						defensores_campo_intermedios += 1
		
		if defensores_campo_intermedios == 0:
			puntaje += 2.5
			desglose.append("Ocasión manifiesta de gol / DOGSO (+2.5)")
	
	# 4. Fuerza Excesiva / Barrida deslizante sin tocar balón
	if es_barrida:
		puntaje += 2.0
		desglose.append("Barrida deslizante sin balón (+2.0)")
	
	return {
		"puntaje": puntaje,
		"desglose": desglose
	}


func registrar_falta(equipo_infractor: int, pos_falta: Vector3, infractor: Jugador3D = null, poseedor: Jugador3D = null, es_barrida: bool = false) -> void:
	if estado != EstadoPartido.EN_JUEGO:
		return
	
	# 1. Verificación y validación estricta del infractor (offender) vs víctima (victim/ball carrier):
	# El infractor es el jugador que comete la entrada, choque o barrida.
	# La víctima es el jugador que poseía el balón o fue derribado.
	if infractor != null and poseedor != null:
		var intercambio_necesario: bool = false
		if poseedor._en_barrida and not infractor._en_barrida:
			intercambio_necesario = true
		elif infractor.tiene_posesion and not poseedor.tiene_posesion:
			intercambio_necesario = true
		elif infractor._t_aturdimiento > 0.0 and poseedor._t_aturdimiento <= 0.0:
			intercambio_necesario = true
		elif infractor._t_bloqueo_recaptura > 0.0 and poseedor._t_bloqueo_recaptura <= 0.0:
			intercambio_necesario = true
		
		if intercambio_necesario:
			var temp: Jugador3D = infractor
			infractor = poseedor
			poseedor = temp

	# 2. Sincronizar equipo_infractor estrictamente con la entidad infractora sancionada
	if infractor != null:
		equipo_infractor = int(infractor.equipo)
	elif poseedor != null:
		equipo_infractor = 1 if int(poseedor.equipo) == 0 else 0
	
	# Fallbacks para infractor y poseedor en caso de invocaciones sin nodo explícito
	if infractor == null:
		var grupo_infractor: String = "equipo_local" if equipo_infractor == 0 else "equipo_visitante"
		var jugs: Array[Node] = get_tree().get_nodes_in_group(grupo_infractor)
		var min_d: float = 999.0
		for n: Node in jugs:
			var j: Jugador3D = n as Jugador3D
			if j and not j.esta_expulsado and j.posicion_tactica != "PORTERO":
				var d: float = j.global_position.distance_to(pos_falta)
				if d < min_d:
					min_d = d
					infractor = j
	
	if poseedor == null:
		var grupo_rival: String = "equipo_visitante" if equipo_infractor == 0 else "equipo_local"
		var jugs_rival: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
		var min_d_p: float = 999.0
		for n: Node in jugs_rival:
			var j: Jugador3D = n as Jugador3D
			if j and not j.esta_expulsado:
				var d: float = j.global_position.distance_to(pos_falta)
				if d < min_d_p:
					min_d_p = d
					poseedor = j
	
	var offender_name: String = infractor.nombre_jugador if (infractor and infractor.nombre_jugador != "") else (infractor.posicion_tactica if infractor else "Infractor")
	var offender_team_name: String = "LOCAL" if equipo_infractor == 0 else "VISITANTE"
	var victim_name: String = poseedor.nombre_jugador if (poseedor and poseedor.nombre_jugador != "") else (poseedor.posicion_tactica if poseedor else "Víctima")
	print("[ARBITRO] Falta cometida por: ", offender_name, " (Equipo: ", offender_team_name, ") sobre: ", victim_name)
	
	# Evaluación algorítmica de severidad (FIFA/IFAB)
	var resultado_eval: Dictionary = evaluar_severidad_falta(infractor, poseedor, pos_falta, es_barrida)
	var puntaje: float = float(resultado_eval.get("puntaje", 0.0))
	
	# 'offender.team' recibe la falta acumulada
	var total_faltas: int = 1
	if GameManager:
		total_faltas = GameManager.registrar_falta_equipo(equipo_infractor)
	
	# 'victim.team' recibe el tiro libre / posesión a favor
	var equipo_favorecido: int = 1 if equipo_infractor == 0 else 0
	
	# Aplicación de Sanciones Disciplinarias según umbrales de severidad
	var nombre_infractor: String = ""
	var dorsal_infractor: int = 0
	if infractor != null:
		nombre_infractor = infractor.nombre_jugador if infractor.nombre_jugador != "" else infractor.posicion_tactica
		dorsal_infractor = infractor.dorsal
	
	var tipo_tarjeta: String = ""
	if puntaje >= 6.5:
		# Tarjeta Roja Directa (Expulsión)
		tipo_tarjeta = "ROJA_DIRECTA"
		print("[ARBITRO] Tarjeta/Sanción aplicada a: ", offender_team_name)
		tarjeta_mostrada.emit(infractor, "ROJA_DIRECTA", puntaje)
		_emitir_anuncio_hud("¡TARJETA ROJA DIRECTA! ¡EXPULSIÓN! #%d %s (Severidad: %.1f)" % [dorsal_infractor, nombre_infractor, puntaje])
		_procesar_expulsion(infractor, false, puntaje)
	elif puntaje >= 3.5:
		if infractor != null:
			infractor.tarjetas_amarillas += 1
			if infractor.tarjetas_amarillas >= 2:
				# Segunda Amarilla -> Tarjeta Roja (Expulsión)
				tipo_tarjeta = "SEGUNDA_AMARILLA"
				print("[ARBITRO] Tarjeta/Sanción aplicada a: ", offender_team_name)
				tarjeta_mostrada.emit(infractor, "SEGUNDA_AMARILLA", puntaje)
				_emitir_anuncio_hud("¡SEGUNDA AMARILLA! ¡EXPULSIÓN! #%d %s" % [dorsal_infractor, nombre_infractor])
				_procesar_expulsion(infractor, true, puntaje)
			else:
				# Tarjeta Amarilla (Amonestación)
				tipo_tarjeta = "AMARILLA"
				print("[ARBITRO] Tarjeta/Sanción aplicada a: ", offender_team_name)
				tarjeta_mostrada.emit(infractor, "AMARILLA", puntaje)
				_emitir_anuncio_hud("¡TARJETA AMARILLA! #%d %s (Severidad: %.1f)" % [dorsal_infractor, nombre_infractor, puntaje])
		else:
			tipo_tarjeta = "AMARILLA"
			print("[ARBITRO] Tarjeta/Sanción aplicada a: ", offender_team_name)
			tarjeta_mostrada.emit(infractor, "AMARILLA", puntaje)
			_emitir_anuncio_hud("¡TARJETA AMARILLA! (Severidad: %.1f)" % puntaje)
	else:
		# Falta común (sin tarjeta)
		_emitir_anuncio_hud("¡FALTA! (%d/5 ACUMULADAS) - TIRO LIBRE DIRECTO" % total_faltas)
	
	# ETAPA 1: DETENCIÓN INMEDIATA Y CÁMARA LENTA AL PITAR FALTA (0.5 s)
	esperando_pitazo_arbitro = true
	if GameManager:
		GameManager.reloj_neto_activo = false
	cuenta_regresiva_4s_actualizada.emit(0.0, false)
	_reproducir_pitido_arbitral()

	_datos_falta_pendiente = {
		"infractor": infractor,
		"victima": poseedor,
		"tipo_tarjeta": tipo_tarjeta,
		"pos_falta": pos_falta,
		"puntaje": puntaje,
		"total_faltas": total_faltas,
		"equipo_favorecido": equipo_favorecido
	}

	# Desaceleración breve (Engine.time_scale = 0.35 durante 0.45 s reales) mientras el balón rueda inerte
	Engine.time_scale = 0.35
	if _tween_cinematica != null and _tween_cinematica.is_valid():
		_tween_cinematica.kill()

	var desglose: Array = resultado_eval.get("desglose", [])
	_tween_cinematica = create_tween().set_ignore_time_scale(true)
	_tween_cinematica.tween_interval(0.45)
	_tween_cinematica.tween_callback(func() -> void:
		Engine.time_scale = 1.0
		_iniciar_secuencia_presentacion_falta(
			infractor,
			poseedor,
			tipo_tarjeta,
			pos_falta,
			puntaje,
			desglose,
			total_faltas,
			equipo_favorecido
		)
	)


# ==============================================================================
# SECUENCIA CINEMÁTICA DE FALTAS, TARJETAS, REPETICIÓN Y VENTANA PRE-PITAZO
# ==============================================================================

## Obtiene la cámara de transmisión principal
func _obtener_camara_transmision() -> CamaraTransmision:
	if _camara_referencia != null and is_instance_valid(_camara_referencia):
		return _camara_referencia
	var arbol: SceneTree = get_tree()
	if arbol != null:
		var cam_g: Node = arbol.get_first_node_in_group("camara_transmision")
		if cam_g is CamaraTransmision:
			_camara_referencia = cam_g as CamaraTransmision
			return _camara_referencia
	if get_parent() != null:
		var cam_p: Node = get_parent().get_node_or_null("Camera3D")
		if cam_p is CamaraTransmision:
			_camara_referencia = cam_p as CamaraTransmision
			return _camara_referencia
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
	if cam is CamaraTransmision:
		_camara_referencia = cam as CamaraTransmision
		return _camara_referencia
	return null


## Obtiene el HUD principal de partido
func _obtener_hud_partido() -> HUDPartido:
	var hud: HUDPartido = get_tree().get_first_node_in_group("hud_partido") as HUDPartido
	if hud and is_instance_valid(hud):
		return hud
	return null


## ETAPA 2: Presentación cinematográfica de falta / repetición en primer plano con máximo detalle (LOD 0)
func _iniciar_secuencia_presentacion_falta(
	infractor: Jugador3D,
	victima: Jugador3D,
	tipo_tarjeta: String,
	pos_falta: Vector3,
	puntaje: float,
	desglose: Array,
	total_faltas: int,
	equipo_favorecido: int
) -> void:
	_en_cinematica_falta = true
	_datos_falta_pendiente = {
		"infractor": infractor,
		"victima": victima,
		"tipo_tarjeta": tipo_tarjeta,
		"pos_falta": pos_falta,
		"puntaje": puntaje,
		"total_faltas": total_faltas,
		"equipo_favorecido": equipo_favorecido
	}
	
	var hud: HUDPartido = _obtener_hud_partido()
	if hud:
		if hud.touch_controls:
			hud.touch_controls.visible = false
		hud.mostrar_boton_omitir(true)
		if tipo_tarjeta != "":
			hud.mostrar_placa_tarjeta(infractor, tipo_tarjeta, puntaje, desglose)
	
	var cam: CamaraTransmision = _obtener_camara_transmision()
	var pos_ref_infractor: Vector3 = infractor.global_position if infractor and is_instance_valid(infractor) else pos_falta
	var pos_ref_victima: Vector3 = victima.global_position if victima and is_instance_valid(victima) else (pos_falta + Vector3(1.0, 0.0, 0.0))

	# 1. Si la falta conlleva Tarjeta Amarilla o Roja: Árbitro 3D + plano contrapicado
	if tipo_tarjeta != "":
		_limpiar_figura_arbitro()
		_figura_arbitro_instancia = FiguraArbitro3DClass.new()
		var contenedor_ar: Node = get_parent() if get_parent() else self
		contenedor_ar.add_child(_figura_arbitro_instancia)
		
		var dir_hacia_infractor: Vector3 = (pos_ref_infractor - pos_ref_victima).normalized()
		if dir_hacia_infractor.length_squared() < 0.01:
			dir_hacia_infractor = Vector3(1.0, 0.0, 0.0)
		
		_figura_arbitro_instancia.aparecer_y_mostrar_tarjeta(pos_ref_infractor, dir_hacia_infractor, tipo_tarjeta)
		
		if infractor and is_instance_valid(infractor) and infractor.has_method("reaccionar_amonestacion"):
			infractor.reaccionar_amonestacion(tipo_tarjeta, _figura_arbitro_instancia.global_position)
		
		if cam:
			cam.activar_camara_cinematica_falta(pos_ref_infractor, _figura_arbitro_instancia.global_position, true)
	else:
		# 2. Falta sin tarjeta: si hay frames en el ring buffer de repetición, reproducir repetición rápida
		var frames_rep: Array = _replay_buffer.obtener_frames(1.5) if _replay_buffer else []
		if frames_rep.size() >= 15:
			if hud:
				hud.mostrar_indicador_repeticion(true)
			if cam:
				cam.activar_camara_repeticion(pos_falta)
			
			var duracion_rep: float = 1.3
			var step_t: float = duracion_rep / float(frames_rep.size())
			var tw_rep: Tween = create_tween().set_ignore_time_scale(true)
			for f_idx: int in range(frames_rep.size()):
				var f_snap = frames_rep[f_idx]
				tw_rep.tween_callback(func() -> void:
					if _en_cinematica_falta and _replay_buffer:
						_replay_buffer.aplicar_snapshot(f_snap, _balon)
				)
				tw_rep.tween_interval(step_t)
			tw_rep.tween_callback(func() -> void:
				if hud:
					hud.mostrar_indicador_repeticion(false)
			)
		else:
			if cam:
				cam.activar_camara_cinematica_falta(pos_ref_infractor, pos_ref_victima, false)

	# 3. Duración de la presentación: 2.2 s reales (saltable en cualquier momento vía botón OMITIR)
	if _tween_cinematica != null and _tween_cinematica.is_valid():
		_tween_cinematica.kill()

	_tween_cinematica = create_tween().set_ignore_time_scale(true)
	_tween_cinematica.tween_interval(2.2)
	_tween_cinematica.tween_callback(func() -> void:
		_finalizar_cinematica_y_pasar_a_pre_pitazo()
	)


## Permite al usuario omitir inmediatamente la cinemática de faltas o repetición (vía botón "OMITIR ⏭")
func omitir_secuencia_falta() -> void:
	if not _en_cinematica_falta and not esperando_pitazo_arbitro:
		return
	if _tween_cinematica != null and _tween_cinematica.is_valid():
		_tween_cinematica.kill()
	Engine.time_scale = 1.0
	_finalizar_cinematica_y_pasar_a_pre_pitazo()


## ETAPA 3: FASE DE POSICIONAMIENTO Y RECONOCIMIENTO PRE-PITAZO (1.3 s SIN CORRER EL TIEMPO)
func _finalizar_cinematica_y_pasar_a_pre_pitazo() -> void:
	_en_cinematica_falta = false
	Engine.time_scale = 1.0

	_limpiar_figura_arbitro()

	var hud: HUDPartido = _obtener_hud_partido()
	if hud:
		hud.mostrar_boton_omitir(false)
		hud.ocultar_placa_tarjeta()
		hud.mostrar_indicador_repeticion(false)
		if hud.touch_controls:
			hud.touch_controls.visible = true

	var cam: CamaraTransmision = _obtener_camara_transmision()
	if cam:
		cam.aplicar_lod_bias_personajes(1.0)

	var pos_falta: Vector3 = _datos_falta_pendiente.get("pos_falta", _pos_saque)
	var equipo_favorecido: int = int(_datos_falta_pendiente.get("equipo_favorecido", 0))
	var total_faltas: int = int(_datos_falta_pendiente.get("total_faltas", 1))

	# 1. Posicionar el balón en el punto de infracción, ubicar barrera a 5m y lanzador
	if total_faltas >= 6:
		iniciar_doble_penalti(equipo_favorecido, total_faltas, pos_falta)
	else:
		var pos_tl: Vector3 = Vector3(clampf(pos_falta.x, -14.0, 14.0), 0.25, clampf(pos_falta.z, -8.5, 8.5))
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, pos_tl, equipo_favorecido, false)

	# Si la falta la cobra la CPU (Visitante), NUNCA activar cámara trasera y restaurar HUD defensivo
	if equipo_favorecido != 0:
		if cam:
			cam.regresar_a_broadcast(0.5)
			cam.make_current()
			cam.aplicar_lod_bias_personajes(1.0)
		_en_ataque_local_actual = false
		_equipo_poseedor_actual = equipo_favorecido
		posesion_cambiada.emit(false, equipo_favorecido)
		if hud and hud.touch_controls:
			hud.touch_controls.actualizar_modo(TouchControls.ModoHUD.DEFENSA)

	# 2. Congelar la cuenta de los 4 segundos durante 1.3 segundos de reconocimiento visual
	esperando_pitazo_arbitro = true
	_timer_timeout = 4.0
	cuenta_regresiva_4s_actualizada.emit(4.0, false)

	if hud:
		hud.mostrar_anuncio("COLOCANDO BARRERA... PREPÁRATE", 1.3)

	if _tween_cinematica != null and _tween_cinematica.is_valid():
		_tween_cinematica.kill()

	_tween_cinematica = create_tween().set_ignore_time_scale(true)
	_tween_cinematica.tween_interval(1.3)
	_tween_cinematica.tween_callback(func() -> void:
		_autorizar_saque_tiro_libre()
	)


## ETAPA 4: PITAZO DE AUTORIZACIÓN E INICIO DE LOS 4 SEGUNDOS REGLAMENTARIOS
func _autorizar_saque_tiro_libre() -> void:
	if estado != EstadoPartido.TIRO_LIBRE and estado != EstadoPartido.DOBLE_PENALTI:
		return

	_reproducir_pitido_arbitral()

	var hud: HUDPartido = _obtener_hud_partido()
	if hud:
		hud.mostrar_anuncio("¡SAQUE AUTORIZADO! (4.0 s)", 1.2)

	esperando_pitazo_arbitro = false
	_timer_timeout = 4.0
	cuenta_regresiva_4s_actualizada.emit(4.0, true)

	if _sacador_actual and is_instance_valid(_sacador_actual):
		_sacador_actual.set_congelado(false)


func _limpiar_figura_arbitro() -> void:
	if _figura_arbitro_instancia != null and is_instance_valid(_figura_arbitro_instancia):
		_figura_arbitro_instancia.desaparecer()
		_figura_arbitro_instancia = null


## Procesa la expulsión de un jugador y activa el periodo de inferioridad numérica (Regla de los 2 Minutos)
func _procesar_expulsion(infractor: Jugador3D, _por_doble_amarilla: bool, _puntaje: float) -> void:
	if infractor == null:
		return
	
	var eq_id: int = int(infractor.equipo)
	var eq_nombre: String = "LOCAL" if eq_id == 0 else "VISITANTE"
	print("[ARBITRO] Tarjeta/Sanción aplicada a: ", eq_nombre)
	
	if eq_id == 0:
		inferioridad_local_activa = true
		tiempo_inferioridad_local = 120.0
		jugador_expulsado_local = infractor
		sancion_2min_actualizada.emit(0, 120.0, true)
	else:
		inferioridad_visitante_activa = true
		tiempo_inferioridad_visitante = 120.0
		jugador_expulsado_visitante = infractor
		sancion_2min_actualizada.emit(1, 120.0, true)
	
	infractor.expulsar_jugador()


## Actualiza los cronómetros de las sanciones de 2 minutos durante el juego neto (EN_JUEGO)
func _actualizar_sanciones_2min(delta: float) -> void:
	if estado != EstadoPartido.EN_JUEGO:
		return
	
	if inferioridad_local_activa:
		tiempo_inferioridad_local -= delta
		if tiempo_inferioridad_local <= 0.0:
			tiempo_inferioridad_local = 0.0
			inferioridad_local_activa = false
			sancion_2min_actualizada.emit(0, 0.0, false)
			_finalizar_inferioridad(0, "TIEMPO_CUMPLIDO")
		else:
			sancion_2min_actualizada.emit(0, tiempo_inferioridad_local, true)
	
	if inferioridad_visitante_activa:
		tiempo_inferioridad_visitante -= delta
		if tiempo_inferioridad_visitante <= 0.0:
			tiempo_inferioridad_visitante = 0.0
			inferioridad_visitante_activa = false
			sancion_2min_actualizada.emit(1, 0.0, false)
			_finalizar_inferioridad(1, "TIEMPO_CUMPLIDO")
		else:
			sancion_2min_actualizada.emit(1, tiempo_inferioridad_visitante, true)


## Finaliza la sanción de inferioridad numérica y gestiona el ingreso del sustituto
func _finalizar_inferioridad(equipo_sancionado: int, motivo: String) -> void:
	var nombre_eq: String = "LOCAL" if equipo_sancionado == 0 else "VISITANTE"
	if motivo == "GOL_RIVAL":
		_emitir_anuncio_hud("¡GOL RIVAL! SANCIÓN DE 2 MIN CANCELADA (ENTRA SUSTITUTO %s)" % nombre_eq)
	else:
		_emitir_anuncio_hud("¡FINALIZÓ SANCIÓN DE 2 MINUTOS! ENTRA SUSTITUTO %s (5 VS 5)" % nombre_eq)
	
	_hacer_ingresar_sustituto(equipo_sancionado)


## Gestiona el ingreso del sustituto desde el banquillo al expirar la sanción o tras gol concedido (FIFA Law 12)
func _hacer_ingresar_sustituto(equipo_sancionado: int) -> void:
	var j_expulsado: Jugador3D = jugador_expulsado_local if equipo_sancionado == 0 else jugador_expulsado_visitante
	var pos_tactica: String = "ALA_IZQ"
	var pos_inicial: Vector3 = Vector3(-2.0 if equipo_sancionado == 0 else 2.0, 0.0, -3.0)
	var nombre_sustituto: String = "Sustituto Loc" if equipo_sancionado == 0 else "Sustituto Vis"
	var dorsal_sustituto: int = 14 if equipo_sancionado == 0 else 15
	
	if j_expulsado and is_instance_valid(j_expulsado):
		pos_tactica = j_expulsado.posicion_tactica
		pos_inicial = j_expulsado._posicion_tactica_inicial
		nombre_sustituto = "Sub %s" % (j_expulsado.nombre_jugador if j_expulsado.nombre_jugador != "" else pos_tactica)
	
	var escena_jugador: PackedScene = load("res://scenes/Jugador3D.tscn")
	if escena_jugador == null:
		return
	
	var sustituto: Jugador3D = escena_jugador.instantiate() as Jugador3D
	if sustituto == null:
		return
	
	sustituto.name = "Sustituto_%s_%d" % ["Local" if equipo_sancionado == 0 else "Vis", Time.get_ticks_msec()]
	sustituto.equipo = Jugador3D.Equipo.LOCAL if equipo_sancionado == 0 else Jugador3D.Equipo.VISITANTE
	sustituto.posicion_tactica = pos_tactica
	sustituto.dorsal = dorsal_sustituto
	sustituto.nombre_jugador = nombre_sustituto
	
	var contenedor: Node = get_parent().get_node_or_null("Jugadores") if get_parent() else null
	if contenedor == null:
		contenedor = get_parent()
	if contenedor == null:
		contenedor = self
	contenedor.add_child(sustituto)
	
	sustituto._posicion_tactica_inicial = pos_inicial
	var pos_banquillo: Vector3 = Vector3(-8.5, 0.0, -11.4) if equipo_sancionado == 0 else Vector3(5.0, 0.0, -11.4)
	sustituto.aplicar_uniforme_equipo(equipo_sancionado)
	sustituto.iniciar_entrada_cancha(pos_banquillo)
	
	if equipo_sancionado == 0:
		jugador_expulsado_local = null
	else:
		jugador_expulsado_visitante = null


## Callback ante cada gol anotado para aplicar la regla oficial de excepción por gol en inferioridad numérica
func _on_gol_anotado(equipo_anotador: int) -> void:
	var eq_anotador_nombre: String = "LOCAL" if equipo_anotador == 0 else "VISITANTE"
	print("[ARBITRO] Gol anotado por Equipo: ", eq_anotador_nombre)
	
	# Regla de Excepción por Gol en Sanción de 2 Minutos (FIFA/IFAB Ley 12):
	# Si ambos equipos están en inferioridad (ej. 4 vs 4), ningún equipo recupera jugadores por gol.
	if inferioridad_local_activa and inferioridad_visitante_activa:
		print("[ARBITRO] Ambos equipos se encuentran en inferioridad numérica (4 vs 4): la sanción continúa.")
		return
	
	# Si el equipo en superioridad (5) anota gol contra el equipo en inferioridad (4):
	# Se cancela la sanción y el equipo sancionado completa sus 5 jugadores con un sustituto.
	if inferioridad_local_activa and equipo_anotador == 1:
		print("[ARBITRO] Gol de VISITANTE (equipo con superioridad): se cancela sanción de 2 min de LOCAL e ingresa sustituto.")
		inferioridad_local_activa = false
		tiempo_inferioridad_local = 0.0
		sancion_2min_actualizada.emit(0, 0.0, false)
		_finalizar_inferioridad(0, "GOL_RIVAL")
	elif inferioridad_visitante_activa and equipo_anotador == 0:
		print("[ARBITRO] Gol de LOCAL (equipo con superioridad): se cancela sanción de 2 min de VISITANTE e ingresa sustituto.")
		inferioridad_visitante_activa = false
		tiempo_inferioridad_visitante = 0.0
		sancion_2min_actualizada.emit(1, 0.0, false)
		_finalizar_inferioridad(1, "GOL_RIVAL")
	elif (inferioridad_local_activa and equipo_anotador == 0) or (inferioridad_visitante_activa and equipo_anotador == 1):
		print("[ARBITRO] Gol anotado por el equipo en inferioridad numérica: la sanción de 2 min NO se cancela y el reloj continúa.")


## Sanciona la Regla Oficial de Futsal de Cesión al Portero:
## Si el portero toca el balón con las manos tras un pase intencional con el pie de un compañero,
## el árbitro señala Tiro Libre Indirecto a favor del rival sobre la línea del área de 6 metros.
func sancionar_cesion_portero_manos(equipo_infractor: int, pos_infraccion: Vector3) -> void:
	if estado != EstadoPartido.EN_JUEGO:
		return
	var equipo_favorecido: int = 1 if equipo_infractor == 0 else 0
	var x_linea_area: float = -14.0 if equipo_infractor == 0 else 14.0
	var z_linea_area: float = clampf(pos_infraccion.z, -3.2, 3.2)
	_reproducir_pitido_arbitral()
	_emitir_anuncio_hud("¡CESIÓN AL PORTERO (MANOS)! TIRO LIBRE INDIRECTO")
	iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, Vector3(x_linea_area, 0.25, z_linea_area), equipo_favorecido, true)


## Sanciona infracción reglamentaria por mano deliberada o posición antinatural en la barrera defensiva.
## Si ocurre dentro del área penal (6m), se pita Penalti. Fuera del área se pita Tiro Libre Directo.
func sancionar_mano_barrera(infractor: Jugador3D, pos_infraccion: Vector3, es_penal: bool) -> void:
	if estado != EstadoPartido.TIRO_LIBRE and estado != EstadoPartido.DOBLE_PENALTI and estado != EstadoPartido.EN_JUEGO:
		return
	var eq_infractor: int = infractor.equipo if infractor != null else 1
	var eq_favorecido: int = 1 if eq_infractor == 0 else 0
	_reproducir_pitido_arbitral()

	if es_penal:
		_emitir_anuncio_hud("¡MANO EN LA BARRERA! ¡PENALTI SANCIONADO!")
		var x_penal: float = 14.0 if eq_favorecido == 0 else -14.0
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, Vector3(x_penal, 0.25, 0.0), eq_favorecido, false)
	else:
		_emitir_anuncio_hud("¡MANO EN LA BARRERA! TIRO LIBRE DIRECTO")
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, pos_infraccion, eq_favorecido, false)


## Ejecuta la regla oficial de 6ª falta acumulada (Tiro Libre Directo sin Barrera):
## - Desactiva por completo la formación de la barrera.
## - Si la falta ocurrió a > 10.0m del arco rival, posiciona automáticamente el balón en el segundo punto penal (10.0m).
## - Si ocurrió entre el área penal (6.0m) y los 10.0m, se ejecuta desde el punto de la falta sin barrera.
## - Todos los jugadores de campo (excepto pateador y arqueros) se sitúan detrás de la línea paralela al balón y a >= 5.0m.
## - El portero rival puede adelantarse hasta un límite de 5.0m respecto al balón.
func iniciar_doble_penalti(equipo_ejecutor: int, num_falta: int = 6, pos_falta: Vector3 = Vector3.ZERO) -> void:
	if _balon == null:
		_conectar_balon()
	
	_sancionando_4s = false
	_equipo_sacador = equipo_ejecutor
	es_tiro_indirecto = false
	toques_en_jugada = 0
	_defensores_barrera_tl.clear()
	_posiciones_barrera_tl.clear()
	_cambiar_estado(EstadoPartido.DOBLE_PENALTI)
	
	var pos_arco_rival: Vector3 = Vector3(20.0 if equipo_ejecutor == 0 else -20.0, 0.0, 0.0)
	var x_segundo_penal: float = 10.0 if equipo_ejecutor == 0 else -10.0
	var usar_punto_falta: bool = false
	if pos_falta != Vector3.ZERO:
		var dist_al_arco: float = Vector2(pos_falta.x, pos_falta.z).distance_to(Vector2(pos_arco_rival.x, pos_arco_rival.z))
		if dist_al_arco <= 10.0:
			usar_punto_falta = true
	
	if usar_punto_falta:
		_pos_saque = Vector3(clampf(pos_falta.x, -14.0, 14.0), 0.25, clampf(pos_falta.z, -8.5, 8.5))
		_emitir_anuncio_hud("¡%dª FALTA! ¡TIRO LIBRE SIN BARRERA DESDE EL PUNTO DE FALTA!" % num_falta)
	else:
		_pos_saque = Vector3(x_segundo_penal, 0.25, 0.0)
		_emitir_anuncio_hud("¡%dª FALTA! ¡DOBLE PENALTI A 10M SIN BARRERA!" % num_falta)
	
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j_limpio: Jugador3D = n as Jugador3D
		if j_limpio:
			j_limpio.establecer_pose_barrera(false)
			j_limpio.fijar_en_saque(false)
			j_limpio.soltar_posesion()
	
	var ejecutor: Jugador3D = _obtener_sacador_centro(equipo_ejecutor)
	var portero_rival: Jugador3D = _obtener_portero(1 if equipo_ejecutor == 0 else 0)
	_sacador_actual = ejecutor
	
	if _balon:
		_balon.configurar_saque_reglamentario(_pos_saque, ejecutor, false)
	
	# Despejar a todos los demás jugadores de campo detrás de la línea del balón y a >= 5.0m (prohibida la barrera)
	_mantener_despeje_doble_penalti()
	
	var pos_balon_plana: Vector3 = Vector3(_pos_saque.x, 0.0, _pos_saque.z)
	var dir_arco: Vector3 = (pos_arco_rival - pos_balon_plana).normalized()
	if dir_arco.length_squared() < 0.01:
		dir_arco = Vector3(1.0 if equipo_ejecutor == 0 else -1.0, 0.0, 0.0)
	
	# El portero rival puede adelantarse hasta un límite máximo de 5.0m respecto al balón
	if portero_rival:
		var pos_gk_adelantado: Vector3 = pos_balon_plana + dir_arco * distancia_barrera_futsal
		if equipo_ejecutor == 0:
			pos_gk_adelantado.x = clampf(pos_gk_adelantado.x, 14.0, 19.35)
		else:
			pos_gk_adelantado.x = clampf(pos_gk_adelantado.x, -19.35, -14.0)
		pos_gk_adelantado.z = clampf(pos_gk_adelantado.z, -1.65, 1.65)
		portero_rival.global_position = Vector3(pos_gk_adelantado.x, 0.0, pos_gk_adelantado.z)
		portero_rival.velocity = Vector3.ZERO
		var dir_mira_gk: Vector3 = (pos_balon_plana - portero_rival.global_position).normalized()
		portero_rival.rotation.y = atan2(-dir_mira_gk.x, -dir_mira_gk.z)
	
	if ejecutor:
		var vec_derecha_dp: Vector3 = Vector3(-dir_arco.z, 0.0, dir_arco.x).normalized()
		var pos_anclaje: Vector3 = pos_balon_plana - dir_arco * 1.45 - vec_derecha_dp * 0.48
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
	var signo_ataque: float = 1.0 if _equipo_sacador == 0 else -1.0
	var x_linea_detras: float = _pos_saque.x - signo_ataque * (distancia_barrera_futsal + 0.35)
	x_linea_detras = clampf(x_linea_detras, -18.5, 18.5)
	var pos_balon_plana: Vector3 = Vector3(_pos_saque.x, 0.0, _pos_saque.z)
	var idx_fila: int = 0
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j == null or j == _sacador_actual:
			continue
		if j.posicion_tactica == "PORTERO":
			# El portero defensor debe respetar los >= 5.0 metros reglamentarios respecto al balón
			if int(j.equipo) != _equipo_sacador:
				var diff_gk: Vector3 = Vector3(j.global_position.x, 0.0, j.global_position.z) - pos_balon_plana
				var d_gk: float = diff_gk.length()
				if d_gk < distancia_barrera_futsal and d_gk > 0.01:
					var npos_gk: Vector3 = pos_balon_plana + diff_gk.normalized() * distancia_barrera_futsal
					npos_gk.x = clampf(npos_gk.x, -19.35, 19.35)
					j.global_position = Vector3(npos_gk.x, 0.0, npos_gk.z)
					j.velocity = Vector3.ZERO
			continue
		
		# Todos los jugadores de campo deben situarse detrás de la línea paralela al balón y a >= 5.0m de distancia
		j.establecer_pose_barrera(false)
		var pos_j_plana: Vector3 = Vector3(j.global_position.x, 0.0, j.global_position.z)
		var delante_de_linea: bool = (_equipo_sacador == 0 and pos_j_plana.x > _pos_saque.x - 0.5) or (_equipo_sacador == 1 and pos_j_plana.x < _pos_saque.x + 0.5)
		var dist_al_balon: float = pos_j_plana.distance_to(pos_balon_plana)
		if delante_de_linea or dist_al_balon < distancia_barrera_futsal:
			var z_lateral: float = -7.5 + float(idx_fila % 4) * 5.0
			if Vector2(x_linea_detras, z_lateral).distance_to(Vector2(_pos_saque.x, _pos_saque.z)) < distancia_barrera_futsal:
				z_lateral = -8.5 if _pos_saque.z >= 0.0 else 8.5
			j.global_position = Vector3(x_linea_detras, 0.0, z_lateral)
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
	
	_reproducir_pitido_arbitral()
	
	if _sacador_actual and is_instance_valid(_sacador_actual):
		_sacador_actual.fijar_en_saque(false)
		_sacador_actual.soltar_posesion()
	
	if estado_previo == EstadoPartido.SAQUE_META:
		# Si el portero demora más de 4s: tiro libre indirecto para el rival al borde del área de 6m
		_emitir_anuncio_hud("¡TIEMPO AGOTADO (4S) DEL PORTERO! TIRO LIBRE INDIRECTO RIVAL")
		var x_borde_area: float = -13.8 if equipo_infractor == 0 else 13.8
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, Vector3(x_borde_area, 0.25, 0.0), equipo_beneficiado, true)
	elif estado_previo == EstadoPartido.TIRO_LIBRE or estado_previo == EstadoPartido.DOBLE_PENALTI:
		# En tiro libre: si vence la cuenta de 4s, se concede tiro libre indirecto al equipo rival en el mismo punto
		_emitir_anuncio_hud("¡TIEMPO AGOTADO (4S)! TIRO LIBRE INDIRECTO RIVAL")
		iniciar_reanudacion(EstadoPartido.TIRO_LIBRE, pos_anterior, equipo_beneficiado, true)
	else:
		# En saque de banda o córner: la posesión pasa al equipo contrario en banda
		_emitir_anuncio_hud("¡TIEMPO AGOTADO (4S)! POSESIÓN RIVAL")
		var z_banda: float = 9.95 if pos_anterior.z >= 0.0 else -9.95
		iniciar_reanudacion(EstadoPartido.SAQUE_BANDA, Vector3(clampf(pos_anterior.x, -18.5, 18.5), 0.25, z_banda), equipo_beneficiado, true)


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


## Gestiona la salida del balón por la línea de fondo fuera de los límites de portería
func _procesar_balon_fuera_linea_fondo(pos_salida: Vector3) -> void:
	var cancha: Node = get_parent()
	if cancha and cancha.has_method("_procesar_saque_fondo"):
		cancha._procesar_saque_fondo(pos_salida)
	else:
		var salio_por_arco_local: bool = pos_salida.x < 0.0
		var ultimo_toque: int = _balon.ultimo_toque_equipo if _balon else 0
		if salio_por_arco_local:
			if ultimo_toque == 1:
				var pos_meta: Vector3 = Vector3(-17.8, 0.25, 0.0)
				iniciar_reanudacion(EstadoPartido.SAQUE_META, pos_meta, 0)
			else:
				var z_corner: float = 9.4 if pos_salida.z > 0.0 else -9.4
				var pos_corner: Vector3 = Vector3(-19.4, 0.25, z_corner)
				iniciar_reanudacion(EstadoPartido.SAQUE_ESQUINA, pos_corner, 1)
		else:
			if ultimo_toque == 0:
				var pos_meta: Vector3 = Vector3(17.8, 0.25, 0.0)
				iniciar_reanudacion(EstadoPartido.SAQUE_META, pos_meta, 1)
			else:
				var z_corner: float = 9.4 if pos_salida.z > 0.0 else -9.4
				var pos_corner: Vector3 = Vector3(19.4, 0.25, z_corner)
				iniciar_reanudacion(EstadoPartido.SAQUE_ESQUINA, pos_corner, 0)


## Valida si un gol anotado cumple con la regla FIFA/IFAB de Tiro Directo vs. Indirecto.
## Si es tiro libre indirecto (o saque de banda/meta) y el balón ingresa al arco con un solo toque
## (`toques_en_jugada == 1`), anula el gol y concede Saque de Meta (`SAQUE_META`) al equipo defensor.
func validar_y_procesar_gol(equipo_que_anoto: int) -> bool:
	if _balon == null:
		_conectar_balon()
	
	if _balon != null and is_instance_valid(_balon):
		if not _balon.es_gol_valido_posicional(equipo_que_anoto == 0):
			return false

		es_tiro_indirecto = _balon.es_tiro_indirecto
		toques_en_jugada = _balon.toques_en_jugada
		if not _balon.es_gol_valido_reglamentario():
			_reproducir_pitido_arbitral()
			_emitir_anuncio_hud("¡GOL ANULADO! TIRO INDIRECTO SIN 2° TOQUE — SAQUE DE META")
			var equipo_defensor: int = 1 if equipo_que_anoto == 0 else 0
			var pos_meta: Vector3 = Vector3(-17.8 if equipo_defensor == 0 else 17.8, 0.25, 0.0)
			iniciar_reanudacion(EstadoPartido.SAQUE_META, pos_meta, equipo_defensor, true)
			return false
	
	return true


## Gestiona la celebración del gol y el saque desde el centro del campo
func iniciar_gol(equipo_que_anoto: int) -> void:
	if _balon == null:
		_conectar_balon()
	
	_cambiar_estado(EstadoPartido.GOL)
	_esperando_toque = false
	gol_anotado.emit(equipo_que_anoto)
	
	if _balon:
		_balon.esta_fuera_de_juego = true
		_balon.detener()
	
	# 1. Congelar a todos los jugadores durante la celebración del gol
	var todos: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	for n: Node in todos:
		var j: Jugador3D = n as Jugador3D
		if j:
			j.establecer_pose_barrera(false)
			j.fijar_en_saque(false)
			j.set_congelado(true)
			j.velocity = Vector3.ZERO
	
	await get_tree().create_timer(t_celebracion_gol).timeout
	
	# 2. Reanudar con saque de centro reglamentario para el equipo que recibió el gol
	var equipo_receptor_gol: int = 1 if equipo_que_anoto == 0 else 0
	iniciar_saque_centro(equipo_receptor_gol)


## Callback cuando el balón es pateado o lanzado por el sacador
func _on_balon_liberado() -> void:
	if estado == EstadoPartido.ENTRENAMIENTO:
		return
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
				j.set_physics_process(true)
				j.es_opcion_de_pase = true
				if j._congelado:
					j.set_congelado(false)
		
		_defensores_barrera_tl.clear()
		_posiciones_barrera_tl.clear()
		_sacador_actual = null
		
		# Restaurar cámara principal de transmisión y LOD reglamentario
		var cam_fin: CamaraTransmision = _obtener_camara_transmision()
		if cam_fin != null and is_instance_valid(cam_fin):
			cam_fin.regresar_a_broadcast(0.75)
			cam_fin.make_current()
			cam_fin.aplicar_lod_bias_personajes(1.0)
		
		_cambiar_estado(EstadoPartido.EN_JUEGO)


## Aplica la distancia reglamentaria de 5.0 metros a todos los rivales del equipo sacador
func _aplicar_regla_5m(reubicacion_inicial: bool = false) -> void:
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


## Configura la barrera rival a exactamente 5.0m del balón en la línea hacia el centro del arco rival:
## `pos_barrera = balon.global_position + (arco_rival.global_position - balon.global_position).normalized() * 5.0`
## - Si la distancia al arco es menor a 12 m: barrera de 3 defensores.
## - Si la distancia al arco es mayor o igual a 12 m: barrera de 2 defensores.
## - Ningún jugador rival puede estar dentro de un radio inferior a 5.0 metros del balón al momento de la orden.
func _configurar_barrera_y_posicionamiento_tiro_libre(equipo_sacador_idx: int, pos_balon: Vector3) -> void:
	_defensores_barrera_tl.clear()
	_posiciones_barrera_tl.clear()

	var pos_arco_rival: Vector3 = Vector3(20.0 if equipo_sacador_idx == 0 else -20.0, 0.0, 0.0)
	var pos_balon_plana: Vector3 = Vector3(pos_balon.x, 0.0, pos_balon.z)
	var dist_al_arco: float = pos_balon_plana.distance_to(pos_arco_rival)

	# Regla Futsal: Menor a 12m -> 3 defensores; Mayor o igual -> 2 defensores
	var num_barrera: int = 3 if dist_al_arco < 12.0 else 2

	# Determinar el poste más cercano al balón y el poste opuesto para posicionamiento del arquero
	var signo_poste_cercano: float = -1.0
	if pos_balon.z > 0.15:
		signo_poste_cercano = 1.0
	elif pos_balon.z < -0.15:
		signo_poste_cercano = -1.0

	# Vector unitario desde el balón hacia el centro del arco rival
	var dir_arco: Vector3 = (pos_arco_rival - pos_balon_plana).normalized()
	if dir_arco.length_squared() < 0.01:
		dir_arco = Vector3(1.0 if equipo_sacador_idx == 0 else -1.0, 0.0, 0.0)

	# Posición reglamentaria de la barrera a exactamente 5.0 metros en la línea hacia el centro del arco rival
	var pos_barrera: Vector3 = pos_balon_plana + dir_arco * distancia_barrera_futsal
	var vec_perp: Vector3 = Vector3(-dir_arco.z, 0.0, dir_arco.x).normalized()

	var grupo_rival: String = "equipo_visitante" if equipo_sacador_idx == 0 else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
	var defensores_campo: Array[Jugador3D] = []
	for n: Node in rivales:
		var j: Jugador3D = n as Jugador3D
		if j and j.posicion_tactica != "PORTERO":
			defensores_campo.append(j)

	# Ordenar rivales por cercanía al punto de la barrera
	defensores_campo.sort_custom(func(a: Jugador3D, b: Jugador3D) -> bool:
		return a.global_position.distance_squared_to(pos_barrera) < b.global_position.distance_squared_to(pos_barrera)
	)

	# Separación compacta hombro con hombro de 0.55 m entre cada defensor de la barrera
	var offsets: Array[float] = []
	if num_barrera == 2:
		offsets = [-0.275, 0.275]
	else:
		offsets = [-0.55, 0.0, 0.55]

	var cantidad_a_ubicar: int = mini(num_barrera, defensores_campo.size())
	for i: int in range(cantidad_a_ubicar):
		var def_barrera: Jugador3D = defensores_campo[i]
		var off: float = offsets[i]
		var pos_exacta_5m: Vector3 = pos_barrera + vec_perp * off
		pos_exacta_5m.x = clampf(pos_exacta_5m.x, -18.8, 18.8)
		pos_exacta_5m.z = clampf(pos_exacta_5m.z, -9.2, 9.2)
		pos_exacta_5m.y = 0.0

		def_barrera.global_position = pos_exacta_5m
		var dir_mira: Vector3 = (pos_balon_plana - pos_exacta_5m).normalized()
		def_barrera.rotation.y = atan2(-dir_mira.x, -dir_mira.z)
		def_barrera.velocity = Vector3.ZERO
		def_barrera.fijar_en_saque(true, pos_exacta_5m)
		def_barrera.establecer_pose_barrera(true)

		_defensores_barrera_tl.append(def_barrera)
		_posiciones_barrera_tl.append(pos_exacta_5m)

	# Posicionar al arquero rival cubriendo el poste opuesto con visión limpia hacia el lanzador
	var portero_rival: Jugador3D = _obtener_portero(1 if equipo_sacador_idx == 0 else 0)
	if portero_rival != null and is_instance_valid(portero_rival):
		var x_gk: float = 19.35 if equipo_sacador_idx == 0 else -19.35
		var z_poste_opuesto: float = -signo_poste_cercano * clampf(0.68 + absf(pos_balon.z) * 0.05, 0.62, 1.12)
		portero_rival.global_position = Vector3(x_gk, 0.0, z_poste_opuesto)
		portero_rival.velocity = Vector3.ZERO
		var dir_mira_gk: Vector3 = (pos_balon_plana - portero_rival.global_position).normalized()
		portero_rival.rotation.y = atan2(-dir_mira_gk.x, -dir_mira_gk.z)

	# Ningún otro defensor rival puede estar dentro de un radio inferior a 5.0 metros del balón
	for i: int in range(cantidad_a_ubicar, defensores_campo.size()):
		var def_libre: Jugador3D = defensores_campo[i]
		def_libre.establecer_pose_barrera(false)
		var diff: Vector3 = def_libre.global_position - pos_balon
		diff.y = 0.0
		if diff.length() < distancia_barrera_futsal:
			var dir_alej: Vector3 = diff.normalized() if diff.length_squared() > 0.01 else -dir_arco
			var pos_reubicada: Vector3 = pos_balon + dir_alej * (distancia_barrera_futsal + 0.35)
			pos_reubicada.x = clampf(pos_reubicada.x, -18.8, 18.8)
			pos_reubicada.z = clampf(pos_reubicada.z, -9.2, 9.2)
			def_libre.global_position = Vector3(pos_reubicada.x, 0.0, pos_reubicada.z)
			def_libre.velocity = Vector3.ZERO
	
	# Compañeros de equipo (excepto el sacador): posicionarse fuera de la barrera listos para pase corto o rebote
	var grupo_propios: String = "equipo_local" if equipo_sacador_idx == 0 else "equipo_visitante"
	var companeros: Array[Node] = get_tree().get_nodes_in_group(grupo_propios)
	var idx_comp: int = 0
	for n: Node in companeros:
		var comp: Jugador3D = n as Jugador3D
		if comp == null or comp == _sacador_actual or comp.posicion_tactica == "PORTERO":
			continue
		var diff_comp: Vector3 = comp.global_position - pos_balon
		diff_comp.y = 0.0
		if diff_comp.length() < 3.2 or comp.global_position.distance_to(pos_barrera) < 2.5:
			var signo_lado: float = -1.0 if idx_comp % 2 == 0 else 1.0
			var pos_apoyo: Vector3 = pos_balon - dir_arco * 1.5 + vec_perp * (signo_lado * (3.5 + float(idx_comp) * 1.2))
			pos_apoyo.x = clampf(pos_apoyo.x, -18.8, 18.8)
			pos_apoyo.z = clampf(pos_apoyo.z, -9.2, 9.2)
			comp.global_position = Vector3(pos_apoyo.x, 0.0, pos_apoyo.z)
			comp.velocity = Vector3.ZERO
		idx_comp += 1


## Mantiene firmes a los defensores de la barrera de tiro libre a 5m y despejado el radio
func _mantener_barrera_tiro_libre() -> void:
	if not _esperando_toque:
		return
	
	# Mantener firmes a los defensores de la barrera en su posición reglamentaria
	for i: int in range(_defensores_barrera_tl.size()):
		var def: Jugador3D = _defensores_barrera_tl[i]
		if def and is_instance_valid(def) and i < _posiciones_barrera_tl.size():
			def.global_position = _posiciones_barrera_tl[i]
			def.velocity = Vector3.ZERO
	
	# Garantizar que ningún otro rival invada el radio de 5.0 metros
	var grupo_rival: String = "equipo_visitante" if _equipo_sacador == 0 else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rival)
	for n: Node in rivales:
		var r: Jugador3D = n as Jugador3D
		if r == null or r.posicion_tactica == "PORTERO" or r in _defensores_barrera_tl:
			continue
		var diff: Vector3 = r.global_position - _pos_saque
		diff.y = 0.0
		var d: float = diff.length()
		if d < distancia_barrera_futsal:
			var dir_rad: Vector3 = diff.normalized() if d > 0.01 else Vector3(1.0, 0.0, 0.0)
			var npos: Vector3 = _pos_saque + dir_rad * (distancia_barrera_futsal + 0.1)
			npos.x = clampf(npos.x, -19.0, 19.0)
			npos.z = clampf(npos.z, -9.5, 9.5)
			r.global_position = Vector3(npos.x, 0.0, npos.z)
			r.velocity = Vector3.ZERO


