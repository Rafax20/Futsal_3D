class_name Jugador3D
extends CharacterBody3D

## Controlador de jugador de futsal 3D Low-Poly con estadísticas OVR (1-99),
## posesión magnética calibrada para evitar robos instantáneos injustos,
## sistema de tiro y pase con potencia variable (mientras más se mantenga, mayor potencia),
## control manual del arquero únicamente cuando atrapa con las manos para distribuir con joystick y pase,
## IA rival balanceada con contención (jockey), pases y disparos, y arqueros reactivos.

enum Equipo {
	LOCAL,
	VISITANTE
}

enum EstadoIA {
	REPOSO,
	PRESIÓN,
	COBERTURA,
	DESMARQUE_APOYO,
	PORTERO_BLOQUEO
}

enum EstadoJugador {
	LIBRE,
	CONDUCIENDO,
	PRESIONANDO,
	CONTENIENDO,
	BARRIDA,
	RECUPERACION,
	PAUSA
}

@export_group("Identidad y Rol")
@export var equipo: Equipo = Equipo.LOCAL:
	set(valor):
		equipo = valor
		if is_node_ready():
			_cargar_ficha_futsal_3d()
			_actualizar_colores_uniforme()

@export var nombre_jugador: String = ""
@export var siglas_equipo: String = "RFC"
@export var dorsal: int = 10
@export var posicion_tactica: String = "PIVOT" ## PORTERO, CIERRE, ALA_IZQ, ALA_DER, PIVOT
@export var es_controlado: bool = false:
	set(valor):
		es_controlado = valor
		if is_node_ready() and indicador_control:
			indicador_control.visible = valor

@export_group("Atributos y Estadísticas OVR (1-99)")
## Velocidad de movimiento y aceleración (afecta velocidad punta y sprint).
@export_range(1.0, 99.0, 1.0) var vel_movimiento: float = 80.0
## Potencia de impacto al disparar a portería.
@export_range(1.0, 99.0, 1.0) var potencia_tiro: float = 80.0
## Precisión para colocar el balón en los postes y reducir dispersión.
@export_range(1.0, 99.0, 1.0) var precision_tiro: float = 78.0
## Visión y curvatura para pases al pie y filtrados al hueco.
@export_range(1.0, 99.0, 1.0) var vision_pase: float = 82.0
## Firmeza magnética y equilibrio al conducir bajo presión.
@export_range(1.0, 99.0, 1.0) var control_balon: float = 84.0
## Capacidad defensiva de recuperación, barrida, presión y robo de pelota.
@export_range(1.0, 99.0, 1.0) var defensa_recuperacion: float = 76.0

@export_group("Estadísticas de Arquero (1-99)")
@export_range(1.0, 99.0, 1.0) var gk_estirada: float = 82.0
@export_range(1.0, 99.0, 1.0) var gk_reflejos: float = 84.0
@export_range(1.0, 99.0, 1.0) var gk_manejo: float = 80.0
@export_range(1.0, 99.0, 1.0) var gk_posicionamiento: float = 82.0
@export_range(1.0, 99.0, 1.0) var gk_saque: float = 80.0

@export_group("Física Base")
@export var velocidad_giro: float = 16.0
@export var gravedad: float = 18.0
@export var multiplicador_sprint: float = 1.22

@export_group("Contención y Separación")
@export var radio_contencion: float = 1.6
@export var radio_frenado: float = 3.0
@export var radio_separacion: float = 1.05
@export var fuerza_separacion: float = 5.5

@export_group("Posesión y Robo")
@export var t_proteccion_recepcion: float = 1.0
@export var t_proteccion_giro: float = 0.5
@export var umbral_giro_cos: float = 0.34
@export var t_cooldown_robo_fallido: float = 1.5
@export var t_cooldown_barrida_fallida: float = 1.2
@export var t_bloqueo_recaptura: float = 0.6

# Referencias a nodos hijos y rig articulado Low-Poly
@onready var visual: Node3D = $Visual
@onready var torso_mesh: MeshInstance3D = $Visual/Torso
@onready var escudo_pecho: MeshInstance3D = get_node_or_null("Visual/Torso/EscudoPecho") as MeshInstance3D
@onready var label_dorsal: Label3D = get_node_or_null("Visual/Torso/LabelDorsal") as Label3D
@onready var label_nombre: Label3D = get_node_or_null("Visual/LabelNombre") as Label3D
@onready var pantalones_mesh: MeshInstance3D = get_node_or_null("Visual/Pantalones") as MeshInstance3D
@onready var pivote_brazo_izq: Node3D = get_node_or_null("Visual/PivoteBrazoIzq") as Node3D
@onready var pivote_brazo_der: Node3D = get_node_or_null("Visual/PivoteBrazoDer") as Node3D
@onready var manga_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoIzq/MangaIzq") as MeshInstance3D
@onready var manga_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoDer/MangaDer") as MeshInstance3D
@onready var mano_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoIzq/ManoIzq") as MeshInstance3D
@onready var mano_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoDer/ManoDer") as MeshInstance3D
@onready var pivote_pierna_izq: Node3D = get_node_or_null("Visual/PivotePiernaIzq") as Node3D
@onready var pivote_pierna_der: Node3D = get_node_or_null("Visual/PivotePiernaDer") as Node3D
@onready var muslo_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/MusloIzq") as MeshInstance3D
@onready var muslo_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/MusloDer") as MeshInstance3D
@onready var media_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/MediaIzq") as MeshInstance3D
@onready var media_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/MediaDer") as MeshInstance3D
@onready var indicador_control: MeshInstance3D = $Visual/IndicadorControl
@onready var control_balon_area: Area3D = $ControlBalonArea
@onready var punto_conduccion: Marker3D = $PuntoConduccion

# Estado de máquina de estados y dinámica
var _estado: EstadoJugador = EstadoJugador.LIBRE
var _congelado: bool = false
var _en_posicion_saque: bool = false
var _pos_anclaje_saque: Vector3 = Vector3.ZERO
var tiene_posesion: bool = false
var tiene_balon_en_manos: bool = false
var _balon_referencia: Balon3D = null
var _direccion_deseada: Vector3 = Vector3.ZERO
var _tiempo_inmunidad_robo: float = 0.0
var _posicion_tactica_inicial: Vector3 = Vector3.ZERO
var _estado_ia: EstadoIA = EstadoIA.REPOSO

# Variables de animación procedural de extremidades
var _fase_carrera: float = 0.0
var _t_anim_patada: float = 0.0

# Variables de giro, bloqueo y aturdimiento
var _dir_previa: Vector3 = Vector3.ZERO
var _t_bloqueo_recaptura: float = 0.0
var _t_aturdimiento: float = 0.0

# Estado de barrida y defensa
var _en_barrida: bool = false
var _tiempo_barrida: float = 0.0
var _barrida_toco_balon: bool = false
var _cooldown_intento_robo: float = 0.0
var _cooldown_decision_ia: float = 0.0
var _tiempo_paradon_reciente: float = 0.0
var _orden_presion_equipo: bool = false

# Entrada móvil / teclado
var direccion_virtual: Vector2 = Vector2.ZERO
var sprint_activo: bool = false
var _sprint_tactil_mantenido: bool = false


func _ready() -> void:
	_posicion_tactica_inicial = global_position
	
	if indicador_control:
		indicador_control.visible = es_controlado
	
	_cargar_ficha_futsal_3d()
	_asignar_grupos()
	_conectar_sensores_balon()
	_actualizar_colores_uniforme()
	call_deferred("_configurar_excepcion_colision_balon")


## Carga la identidad, dorsal y estadísticas individuales desde la base de datos Futsal_3D
func _cargar_ficha_futsal_3d() -> void:
	var es_loc: bool = (equipo == Equipo.LOCAL)
	var info_eq: Dictionary = Futsal_3D.obtener_info_equipo(es_loc)
	if not info_eq.is_empty():
		siglas_equipo = str(info_eq.get("siglas", "RFC" if es_loc else "ASF"))
	
	var ficha: Dictionary = Futsal_3D.obtener_ficha_jugador(es_loc, posicion_tactica)
	if not ficha.is_empty():
		nombre_jugador = str(ficha.get("nombre", posicion_tactica))
		dorsal = int(ficha.get("dorsal", dorsal))
		if posicion_tactica == "PORTERO":
			vel_movimiento = float(ficha.get("ritmo", 65.0))
			gk_estirada = float(ficha.get("gk_estirada", 84.0))
			gk_reflejos = float(ficha.get("gk_reflejos", 85.0))
			gk_manejo = float(ficha.get("gk_manejo", 81.0))
			gk_posicionamiento = float(ficha.get("gk_posicionamiento", 83.0))
			gk_saque = float(ficha.get("gk_saque", 81.0))
			vision_pase = gk_saque
			control_balon = gk_manejo
			defensa_recuperacion = gk_reflejos
		else:
			vel_movimiento = float(ficha.get("ritmo", vel_movimiento))
			potencia_tiro = float(ficha.get("tiro", potencia_tiro))
			precision_tiro = clampf(float(ficha.get("tiro", precision_tiro)) * 0.96, 50.0, 99.0)
			vision_pase = float(ficha.get("pase", vision_pase))
			control_balon = float(ficha.get("regate", control_balon))
			defensa_recuperacion = float(ficha.get("defensa", defensa_recuperacion))
	
	if label_dorsal:
		label_dorsal.text = str(dorsal)
	if label_nombre:
		label_nombre.text = "%s (%d)" % [nombre_jugador, get_media_ovr()]


## Ancla o libera al jugador en el punto de saque reglamentario (sin poder desplazarse hasta patear)
func fijar_en_saque(activo: bool, pos_anclaje: Vector3 = Vector3.ZERO) -> void:
	_en_posicion_saque = activo
	if activo:
		_pos_anclaje_saque = pos_anclaje
		global_position = pos_anclaje
		velocity = Vector3.ZERO


func _configurar_excepcion_colision_balon() -> void:
	var balon: Balon3D = _obtener_balon_juego()
	if balon and is_instance_valid(balon):
		add_collision_exception_with(balon)
		balon.add_collision_exception_with(self)


func _asignar_grupos() -> void:
	add_to_group("jugadores_futsal")
	if equipo == Equipo.LOCAL:
		add_to_group("equipo_local")
	else:
		add_to_group("equipo_visitante")
	
	if es_controlado:
		add_to_group("jugador_activo")


## Retorna true si el jugador está en condiciones físicas de controlar el balón
func puede_tomar_balon() -> bool:
	if _t_bloqueo_recaptura > 0.0 or _t_aturdimiento > 0.0 or _congelado:
		return false
	var balon: Balon3D = _obtener_balon_juego()
	if balon == null or not is_instance_valid(balon):
		return false
	if balon.has_method("puede_ser_capturado_por") and not balon.puede_ser_capturado_por(self):
		return false
	if balon.has_method("puede_ser_capturado") and not balon.puede_ser_capturado():
		return false
	return true


## Fija el estado de congelamiento del jugador y fuerza el estado PAUSA
func set_congelado(v: bool) -> void:
	_congelado = v
	if v:
		_estado = EstadoJugador.PAUSA
		velocity = Vector3.ZERO
	else:
		_actualizar_estado()


## Retorna true si el portador es vulnerable a intentos de robo
func puede_ser_robado() -> bool:
	return _tiempo_inmunidad_robo <= 0.0 and not tiene_balon_en_manos and not _en_posicion_saque



## Deriva el estado dinámico del jugador según posesión, barrida, congelado y cercanía al portador rival
func _actualizar_estado() -> void:
	var balon: Balon3D = _obtener_balon_juego()
	
	# Garantía de sincronización: si Balon3D no nos tiene como portador_actual, limpiar tiene_posesion
	if tiene_posesion:
		if balon == null or not is_instance_valid(balon) or not balon.esta_siendo_conducido() or balon.portador_actual != self:
			tiene_posesion = false
			tiene_balon_en_manos = false
	elif balon != null and is_instance_valid(balon) and balon.esta_siendo_conducido() and balon.portador_actual == self:
		tiene_posesion = true
		_balon_referencia = balon
	
	# El arquero NUNCA debe quedar controlado por el usuario si no tiene el balón
	if posicion_tactica == "PORTERO" and es_controlado and not tiene_posesion:
		cambiar_a_mas_cercano_al_balon(false)
	
	if _congelado:
		_estado = EstadoJugador.PAUSA
		return
	
	if _en_barrida:
		_estado = EstadoJugador.BARRIDA
		return
	
	if _t_aturdimiento > 0.0:
		_estado = EstadoJugador.RECUPERACION
		return
	
	if tiene_posesion:
		_estado = EstadoJugador.CONDUCIENDO
		return
	
	var rival_portador: Jugador3D = null
	if balon and is_instance_valid(balon) and balon.esta_siendo_conducido():
		var p: Jugador3D = balon.portador_actual as Jugador3D
		if p and p.equipo != equipo:
			rival_portador = p
	
	if rival_portador != null:
		var d_rival: float = global_position.distance_to(rival_portador.global_position)
		if d_rival <= radio_contencion:
			_estado = EstadoJugador.CONTENIENDO
		elif d_rival <= radio_frenado:
			_estado = EstadoJugador.PRESIONANDO
		else:
			_estado = EstadoJugador.LIBRE
	else:
		_estado = EstadoJugador.LIBRE


func _physics_process(delta: float) -> void:
	_actualizar_estado()
	
	if _t_anim_patada > 0.0:
		_t_anim_patada -= delta
	
	match _estado:
		EstadoJugador.PAUSA:
			velocity = Vector3.ZERO
			_animar_extremidades(delta)
			return
		_:
			pass
	
	if _tiempo_inmunidad_robo > 0.0:
		_tiempo_inmunidad_robo -= delta
	if _cooldown_intento_robo > 0.0:
		_cooldown_intento_robo -= delta
	if _cooldown_decision_ia > 0.0:
		_cooldown_decision_ia -= delta
	if _tiempo_paradon_reciente > 0.0:
		_tiempo_paradon_reciente -= delta
	if _t_bloqueo_recaptura > 0.0:
		_t_bloqueo_recaptura -= delta
	if _t_aturdimiento > 0.0:
		_t_aturdimiento -= delta
	
	# Protección contra caídas al vacío / abismo
	if global_position.y < -0.1:
		global_position.y = 0.0
		velocity.y = 0.0
	
	# Límites suaves del pabellón para evitar atravesar vallas (y área penal si el portero tiene el balón en manos)
	if posicion_tactica == "PORTERO" and tiene_balon_en_manos:
		if equipo == Equipo.LOCAL:
			global_position.x = clampf(global_position.x, -19.5, -14.2)
		else:
			global_position.x = clampf(global_position.x, 14.2, 19.5)
		global_position.z = clampf(global_position.z, -3.2, 3.2)
	else:
		global_position.x = clampf(global_position.x, -20.2, 20.2)
		global_position.z = clampf(global_position.z, -10.5, 10.5)
	
	# Gravedad básica
	if not is_on_floor():
		velocity.y -= gravedad * delta
	else:
		velocity.y = 0.0
	
	match _estado:
		EstadoJugador.BARRIDA:
			_tiempo_barrida -= delta
			if _chequear_impacto_barrida():
				_barrida_toco_balon = true
			if _tiempo_barrida <= 0.0:
				_en_barrida = false
				if not _barrida_toco_balon:
					_t_aturdimiento = t_cooldown_barrida_fallida
		_:
			if es_controlado:
				_procesar_input_jugador()
			else:
				_procesar_ia_tactica(delta)
			
			_aplicar_movimiento(delta)
	
	if not _en_posicion_saque:
		move_and_slide()
	else:
		global_position = _pos_anclaje_saque
		velocity = Vector3.ZERO
	
	# Captura proactiva del balón libre
	_chequear_proximidad_balon()
	
	_gestionar_conduccion_y_robos(delta)
	_animar_extremidades(delta)


func _conectar_sensores_balon() -> void:
	if control_balon_area:
		control_balon_area.body_entered.connect(_on_control_balon_area_body_entered)
		control_balon_area.body_exited.connect(_on_control_balon_area_body_exited)


func _on_control_balon_area_body_entered(body: Node3D) -> void:
	if body is Balon3D:
		var balon: Balon3D = body as Balon3D
		if not puede_tomar_balon():
			return
		if not balon.esta_siendo_conducido() and not balon.esta_fuera_de_juego:
			if posicion_tactica == "PORTERO" and _esta_en_area_propia(balon.global_position):
				atrapar_con_manos(balon)
			else:
				tomar_posesion(balon)
		elif balon.portador_actual != self:
			var portador: Jugador3D = balon.portador_actual as Jugador3D
			if portador and portador.equipo != equipo:
				_intentar_robo(portador, balon)


func _on_control_balon_area_body_exited(body: Node3D) -> void:
	if body == _balon_referencia and not tiene_posesion:
		_balon_referencia = null


func _esta_en_area_propia(pos: Vector3) -> bool:
	var linea_meta_x: float = -19.4 if equipo == Equipo.LOCAL else 19.4
	return abs(pos.x - linea_meta_x) < 5.5 and abs(pos.z) < 3.6


## Recoge el balón si está libre en las cercanías
func _chequear_proximidad_balon() -> void:
	if tiene_posesion or _en_barrida:
		return
	if not puede_tomar_balon():
		return
	
	var balon: Balon3D = _obtener_balon_juego()
	if balon == null or not is_instance_valid(balon):
		return
	if balon.esta_fuera_de_juego:
		return
	
	# Si el balón está completamente libre, se toma con facilidad al tocarlo
	if not balon.esta_siendo_conducido():
		var dist: float = global_position.distance_to(balon.global_position)
		var radio_captura: float = 1.15 if (es_controlado and balon.ultimo_toque_equipo == int(equipo)) else 0.95
		if dist < radio_captura:
			if posicion_tactica == "PORTERO" and _esta_en_area_propia(balon.global_position):
				atrapar_con_manos(balon)
			else:
				tomar_posesion(balon)


## Toma posesión magnética del balón con escudo protector inicial
func tomar_posesion(balon: Balon3D) -> void:
	if balon == null:
		return
	_balon_referencia = balon
	tiene_posesion = true
	tiene_balon_en_manos = false
	_tiempo_inmunidad_robo = t_proteccion_recepcion
	balon.capturar_por(self)
	
	# Si el jugador que toma posesión pertenece al equipo LOCAL, darle siempre el control activo al usuario
	if equipo == Equipo.LOCAL and not es_controlado:
		_asignar_control_a_este_jugador()
	elif equipo == Equipo.VISITANTE and posicion_tactica == "PORTERO":
		_cooldown_decision_ia = 0.65


## El portero atrapa con las manos: posesión absoluta protegida
func atrapar_con_manos(balon: Balon3D) -> void:
	if balon == null:
		return
	_balon_referencia = balon
	tiene_posesion = true
	tiene_balon_en_manos = true
	_tiempo_inmunidad_robo = 9999.0 # Inmune a robos con la mano
	balon.capturar_por(self)
	
	if equipo == Equipo.LOCAL:
		_asignar_control_a_este_jugador()
		_emitir_anuncio_hud("¡EL ARQUERO TIENE EL BALÓN! APUNTA Y PRESIONA PASE")
	else:
		_cooldown_decision_ia = 0.75


func _asignar_control_a_este_jugador() -> void:
	var dir_heredada: Vector2 = direccion_virtual
	var sprint_heredado: bool = _sprint_tactil_mantenido
	
	var activos: Array[Node] = get_tree().get_nodes_in_group("jugador_activo")
	for act: Node in activos:
		var j_act: Jugador3D = act as Jugador3D
		if j_act and j_act != self:
			if j_act.direccion_virtual.length_squared() > 0.001:
				dir_heredada = j_act.direccion_virtual
			if j_act._sprint_tactil_mantenido:
				sprint_heredado = true
			j_act.direccion_virtual = Vector2.ZERO
			j_act._sprint_tactil_mantenido = false
			j_act.sprint_activo = false
			j_act.es_controlado = false
			j_act.remove_from_group("jugador_activo")
	
	es_controlado = true
	direccion_virtual = dir_heredada
	_sprint_tactil_mantenido = sprint_heredado
	sprint_activo = sprint_heredado
	if not is_in_group("jugador_activo"):
		add_to_group("jugador_activo")
	
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and "ruta_jugador_activo" in cam:
		cam.ruta_jugador_activo = cam.get_path_to(self)


## Libera la posesión del balón
func soltar_posesion() -> void:
	tiene_posesion = false
	tiene_balon_en_manos = false
	if _balon_referencia and _balon_referencia.portador_actual == self:
		_balon_referencia.portador_actual = null


## Intento de robo justo y equilibrado con factores angulares y cooldown de fallo
func _intentar_robo(portador: Jugador3D, balon: Balon3D) -> void:
	if not portador.puede_ser_robado() or not puede_tomar_balon():
		return
	
	var def: float = defensa_recuperacion
	var ctrl: float = portador.control_balon
	var facing_portador: Vector3 = -portador.global_transform.basis.z.normalized()
	var dir_hacia_ladron: Vector3 = (global_position - portador.global_position).normalized()
	var f_ang: float = 1.0 - 0.35 * facing_portador.dot(dir_hacia_ladron)
	
	var prob: float = clampf((def / (def + ctrl * 1.6)) * 0.4 * f_ang, 0.05, 0.6)
	
	if randf() < prob:
		portador.soltar_posesion()
		portador._t_bloqueo_recaptura = t_bloqueo_recaptura
		tomar_posesion(balon)
	else:
		_cooldown_intento_robo = t_cooldown_robo_fallido


## Mantiene el balón en los pies o manos del portador
func _gestionar_conduccion_y_robos(delta: float) -> void:
	if not tiene_posesion or _balon_referencia == null or not is_instance_valid(_balon_referencia):
		return
	if not _balon_referencia.esta_siendo_conducido() or _balon_referencia.portador_actual != self:
		tiene_posesion = false
		tiene_balon_en_manos = false
		return
	
	if tiene_balon_en_manos:
		# Balón a la altura de las manos / pecho del arquero
		var pos_manos: Vector3 = global_position - global_transform.basis.z * 0.58 + Vector3(0.0, 0.85, 0.0)
		_balon_referencia.conducir_hacia(pos_manos, delta, 99.0, self)
	else:
		var pos_destino: Vector3 = punto_conduccion.global_position if punto_conduccion else global_position - global_transform.basis.z * 0.62
		_balon_referencia.conducir_hacia(pos_destino, delta, control_balon, self)


func _procesar_input_jugador() -> void:
	var dx: float = 0.0
	var dz: float = 0.0
	
	if Input.is_key_pressed(KEY_A) or Input.is_action_pressed("ui_left"):
		dx -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_action_pressed("ui_right"):
		dx += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_action_pressed("ui_up"):
		dz -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_action_pressed("ui_down"):
		dz += 1.0
	
	if Input.is_key_pressed(KEY_SHIFT):
		sprint_activo = true
	elif not _sprint_tactil_mantenido:
		sprint_activo = false
	
	if direccion_virtual.length_squared() > 0.01:
		_direccion_deseada = Vector3(direccion_virtual.x, 0.0, direccion_virtual.y).normalized()
	else:
		var dir_plana: Vector2 = Vector2(dx, dz)
		if dir_plana.length_squared() > 0.0:
			dir_plana = dir_plana.normalized()
			_direccion_deseada = Vector3(dir_plana.x, 0.0, dir_plana.y)
		else:
			_direccion_deseada = Vector3.ZERO
	
	# Protección adicional al girar bruscamente con posesión
	if tiene_posesion and _dir_previa.length() > 0.5 and _dir_previa.dot(_direccion_deseada) < umbral_giro_cos:
		_tiempo_inmunidad_robo = maxf(_tiempo_inmunidad_robo, t_proteccion_giro)
	_dir_previa = _direccion_deseada


# ==============================================================================
# ACCIONES CONTEXTUALES CON CARGA DE POTENCIA (FC MOBILE / EFOOTBALL)
# ==============================================================================

## Acción del Botón Rojo (Ataque: TIRO | Defensa: ENTRADA / BARRIDA)
func accion_principal_presionada(potencia: float = 0.5) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if tiene_posesion or (dist_balon < 1.35 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and puede_tomar_balon():
			tomar_posesion(balon)
		ejecutar_tiro(potencia)
	else:
		ejecutar_barrida()


## Acción del Botón Azul (Ataque: PASE | Defensa: CAMBIO DE JUGADOR)
func accion_pase_presionada(potencia: float = 0.5) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if tiene_posesion or (dist_balon < 1.35 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and puede_tomar_balon():
			tomar_posesion(balon)
		ejecutar_pase(potencia)
	else:
		cambiar_a_mas_cercano_al_balon()


## Acción del Botón Verde (Ataque: HUECO | Defensa: PRESIÓN DE EQUIPO)
func accion_hueco_presionada(potencia: float = 0.5) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if tiene_posesion or (dist_balon < 1.35 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and puede_tomar_balon():
			tomar_posesion(balon)
		ejecutar_pase_hueco(potencia)
	else:
		ordenar_presion_equipo()


## Disparo colocado con potencia dependiente del tiempo de carga y estadísticas del tirador
func ejecutar_tiro(potencia: float = 0.5) -> void:
	if not tiene_posesion or _balon_referencia == null:
		return
	
	var era_portero_local: bool = (posicion_tactica == "PORTERO" and equipo == Equipo.LOCAL and es_controlado)
	var arco_x: float = 20.0 if equipo == Equipo.LOCAL else -20.0
	var objetivo_z: float = 0.0
	
	# Porterías de 3.7m de ancho (postes en ±1.85m): colocar hacia los ángulos (±1.48m)
	if _direccion_deseada.z < -0.18:
		objetivo_z = -1.48
	elif _direccion_deseada.z > 0.18:
		objetivo_z = 1.48
	else:
		objetivo_z = -1.12 if randf() > 0.5 else 1.12
	
	var presion: float = calcular_presion_rival()
	var error_dispersion: float = ((99.0 - precision_tiro) / 99.0 * 0.28) + (presion * 0.22)
	
	# Altura del disparo según la carga de potencia (más tiempo presionado = tiro más potente y alto)
	var elevacion_y: float = lerpf(0.28, 1.45, clampf(potencia, 0.0, 0.92))
	if potencia > 0.92:
		error_dispersion += 0.18
		elevacion_y = randf_range(1.35, 2.05)
	
	var z_colocado: float = clampf(objetivo_z + randf_range(-error_dispersion, error_dispersion), -1.72, 1.72)
	var destino_tiro: Vector3 = Vector3(arco_x, elevacion_y, z_colocado)
	var vector_tiro: Vector3 = (destino_tiro - _balon_referencia.global_position).normalized()
	
	# Potencia escalada notoriamente por el tiempo de carga del botón y atributo potencia_tiro
	var fuerza_total: float = 10.5 + (potencia_tiro / 99.0) * 5.5 + (potencia * 15.5)
	var impulso_final: Vector3 = vector_tiro * fuerza_total + Vector3(0.0, 0.65 + potencia * 0.55, 0.0)
	
	_en_posicion_saque = false
	_t_anim_patada = 0.28
	soltar_posesion()
	_t_bloqueo_recaptura = 0.4
	_balon_referencia.liberar(impulso_final, int(equipo))
	
	if era_portero_local:
		cambiar_a_mas_cercano_al_balon(false)


## Pase con fuerza y alcance calibrado por la barra de potencia
func ejecutar_pase(potencia: float = 0.5) -> void:
	if not tiene_posesion or _balon_referencia == null:
		return
	
	var dir_por_defecto: Vector3 = -global_transform.basis.z.normalized()
	if posicion_tactica == "PORTERO":
		dir_por_defecto = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	
	var dir_busqueda: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else dir_por_defecto
	var mejor_companero: Jugador3D = _buscar_mejor_receptor(dir_busqueda)
	
	var presion: float = calcular_presion_rival()
	var error_total_rad: float = ((99.0 - vision_pase) / 99.0 * 0.12) + (presion * 0.12)
	var desvio_angulo: float = randf_range(-error_total_rad, error_total_rad)
	
	# Potencia escalada por carga de botón
	var fuerza_pase: float = 8.0 + (potencia * 11.5) + (vision_pase / 99.0) * 2.5
	
	_en_posicion_saque = false
	_t_anim_patada = 0.26
	
	if mejor_companero != null:
		var target: Vector3 = mejor_companero.global_position + (mejor_companero.velocity * 0.22)
		var dist_comp: float = _balon_referencia.global_position.distance_to(target)
		fuerza_pase = clampf(maxf(fuerza_pase, dist_comp * 1.12), 7.8, 21.0)
		var dir_pase: Vector3 = (target - _balon_referencia.global_position).rotated(Vector3.UP, desvio_angulo).normalized()
		
		soltar_posesion()
		_t_bloqueo_recaptura = 0.4
		_balon_referencia.liberar(dir_pase * fuerza_pase + Vector3(0.0, 0.12, 0.0), int(equipo))
		
		# Transferir el foco al receptor (si es jugador de campo; si se pasa al arquero, el arquero toma el foco al recibirla)
		if equipo == Equipo.LOCAL and es_controlado:
			if mejor_companero.posicion_tactica != "PORTERO":
				_transferir_control_a(mejor_companero)
			elif posicion_tactica == "PORTERO":
				cambiar_a_mas_cercano_al_balon(false)
	else:
		var dir_defecto: Vector3 = dir_por_defecto.rotated(Vector3.UP, desvio_angulo).normalized()
		soltar_posesion()
		_t_bloqueo_recaptura = 0.4
		_balon_referencia.liberar(dir_defecto * fuerza_pase + Vector3(0.0, 0.12, 0.0), int(equipo))
		if posicion_tactica == "PORTERO" and equipo == Equipo.LOCAL and es_controlado:
			cambiar_a_mas_cercano_al_balon(false)


## Pase al hueco proyectado en carrera
func ejecutar_pase_hueco(potencia: float = 0.5) -> void:
	if not tiene_posesion or _balon_referencia == null:
		return
	
	var dir_por_defecto: Vector3 = -global_transform.basis.z.normalized()
	if posicion_tactica == "PORTERO":
		dir_por_defecto = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	
	var dir_busqueda: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else dir_por_defecto
	var companero: Jugador3D = _buscar_mejor_receptor(dir_busqueda)
	
	if companero != null and companero.posicion_tactica != "PORTERO":
		var presion: float = calcular_presion_rival()
		var error_total_rad: float = ((99.0 - vision_pase) / 99.0 * 0.14) + (presion * 0.14)
		var desvio_angulo: float = randf_range(-error_total_rad, error_total_rad)
		
		var avance_ofensivo: Vector3 = Vector3(1.0, 0.0, 0.0) if equipo == Equipo.LOCAL else Vector3(-1.0, 0.0, 0.0)
		var distancia_proyeccion: float = 1.8 + potencia * 4.0
		var punto_hueco: Vector3 = companero.global_position + avance_ofensivo * distancia_proyeccion
		punto_hueco.x = clampf(punto_hueco.x, -18.5, 18.5)
		punto_hueco.z = clampf(punto_hueco.z, -9.0, 9.0)
		
		var dir_hueco: Vector3 = (punto_hueco - _balon_referencia.global_position).rotated(Vector3.UP, desvio_angulo).normalized()
		var fuerza: float = 8.5 + potencia * 12.0
		
		_en_posicion_saque = false
		_t_anim_patada = 0.26
		soltar_posesion()
		_t_bloqueo_recaptura = 0.4
		_balon_referencia.liberar(dir_hueco * fuerza + Vector3(0.0, 0.15, 0.0), int(equipo))
		
		if equipo == Equipo.LOCAL and es_controlado:
			_transferir_control_a(companero)
	else:
		ejecutar_pase(potencia)


## Barrida defensiva deslizante para robar el balón
func ejecutar_barrida() -> void:
	if _en_barrida or tiene_posesion or _t_aturdimiento > 0.0 or _en_posicion_saque:
		return
	
	_en_barrida = true
	_tiempo_barrida = 0.35
	_barrida_toco_balon = false
	var dir_barrida: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else -global_transform.basis.z.normalized()
	velocity = dir_barrida * 9.2
	
	_emitir_anuncio_hud("¡ENTRADA!")
	if _chequear_impacto_barrida():
		_barrida_toco_balon = true


func _chequear_impacto_barrida() -> bool:
	var balon: Balon3D = _obtener_balon_juego()
	if balon == null or not is_instance_valid(balon):
		return false
	
	var dist_balon: float = global_position.distance_to(balon.global_position)
	if dist_balon < 1.6:
		if balon.esta_siendo_conducido() and balon.portador_actual != self:
			var portador: Jugador3D = balon.portador_actual as Jugador3D
			if portador and portador.equipo != equipo:
				if portador.puede_ser_robado() and puede_tomar_balon():
					portador.soltar_posesion()
					portador._t_bloqueo_recaptura = t_bloqueo_recaptura
					if randf() < 0.65:
						tomar_posesion(balon)
					else:
						var dir_despeje: Vector3 = -global_transform.basis.z.normalized() * 9.0 + Vector3(0, 1.2, 0)
						balon.liberar(dir_despeje, int(equipo))
					return true
		elif not balon.esta_siendo_conducido():
			if puede_tomar_balon():
				tomar_posesion(balon)
				return true
			else:
				var dir_despeje: Vector3 = -global_transform.basis.z.normalized() * 9.0 + Vector3(0, 1.2, 0)
				balon.liberar(dir_despeje, int(equipo))
				return true
	return false


## Cambia al jugador de campo más cercano al balón
func cambiar_a_mas_cercano_al_balon(mostrar_anuncio: bool = true) -> void:
	if equipo != Equipo.LOCAL:
		return
	
	var balon: Balon3D = _obtener_balon_juego()
	var pos_ref: Vector3 = balon.global_position if balon else global_position
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	
	for n: Node in locales:
		var jug: Jugador3D = n as Jugador3D
		if jug and jug != self and jug.posicion_tactica != "PORTERO":
			var d: float = jug.global_position.distance_to(pos_ref)
			if d < min_dist:
				min_dist = d
				mas_cercano = jug
	
	if mas_cercano != null:
		_transferir_control_a(mas_cercano)
		if mostrar_anuncio:
			_emitir_anuncio_hud("CAMBIO DE JUGADOR")


func ordenar_presion_equipo() -> void:
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	for n: Node in locales:
		var jug: Jugador3D = n as Jugador3D
		if jug and not jug.es_controlado and jug.posicion_tactica != "PORTERO":
			jug._orden_presion_equipo = true
	_emitir_anuncio_hud("¡PRESIÓN DE EQUIPO!")


func calcular_presion_rival() -> float:
	var rivales_grupo: String = "equipo_visitante" if equipo == Equipo.LOCAL else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(rivales_grupo)
	var presion_acumulada: float = 0.0
	
	for n: Node in rivales:
		var rival: Jugador3D = n as Jugador3D
		if rival and rival.posicion_tactica != "PORTERO":
			var dist: float = global_position.distance_to(rival.global_position)
			if dist < 2.8:
				var vector_rival: Vector3 = (rival.global_position - global_position).normalized()
				var alineacion_presion: float = maxf(0.0, -global_transform.basis.z.dot(vector_rival))
				presion_acumulada += ((2.8 - dist) / 2.8) * (0.6 + alineacion_presion * 0.4)
	
	return clampf(presion_acumulada, 0.0, 1.0)


func _buscar_mejor_receptor(direccion: Vector3) -> Jugador3D:
	var grupo_amigos: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
	var companeros: Array[Node] = get_tree().get_nodes_in_group(grupo_amigos)
	
	var dir_norm_input: Vector3 = direccion.normalized() if direccion.length_squared() > 0.001 else Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	var apunta_atras_al_arquero: bool = (equipo == Equipo.LOCAL and dir_norm_input.x < -0.45) or (equipo == Equipo.VISITANTE and dir_norm_input.x > 0.45)
	
	var mejor: Jugador3D = null
	var mejor_puntuacion: float = -999.0
	var fallback_campo: Jugador3D = null
	var mejor_puntaje_fallback: float = -999.0
	
	for nodo: Node in companeros:
		if nodo == self or not (nodo is Jugador3D):
			continue
		var jug: Jugador3D = nodo as Jugador3D
		
		var vector_hacia: Vector3 = (jug.global_position - global_position)
		vector_hacia.y = 0.0
		var dist: float = vector_hacia.length()
		if dist < 0.8 or dist > 34.0:
			continue
		
		var dir_normalizada: Vector3 = vector_hacia.normalized()
		var similitud_angulo: float = dir_norm_input.dot(dir_normalizada)
		
		# El portero solo es elegible si un jugador de campo apunta claramente hacia su propio arco
		if jug.posicion_tactica == "PORTERO":
			if posicion_tactica != "PORTERO" and apunta_atras_al_arquero and similitud_angulo > 0.55:
				var puntaje_arq: float = similitud_angulo * 2.2 - (dist * 0.025)
				if puntaje_arq > mejor_puntuacion:
					mejor_puntuacion = puntaje_arq
					mejor = jug
			continue
		
		# Bonificación si el compañero está desmarcado (lejos de defensores rivales)
		var presion_comp: float = jug.calcular_presion_rival()
		var bonus_desmarque: float = (1.0 - presion_comp) * 0.45
		var puntaje: float = similitud_angulo * 2.2 - (dist * 0.025) + bonus_desmarque + (vision_pase * 0.005)
		
		if puntaje > mejor_puntaje_fallback:
			mejor_puntaje_fallback = puntaje
			fallback_campo = jug
		
		if similitud_angulo > 0.05 and puntaje > mejor_puntuacion:
			mejor_puntuacion = puntaje
			mejor = jug
	
	if mejor != null:
		return mejor
	return fallback_campo


func _transferir_control_a(nuevo_jugador: Jugador3D) -> void:
	if nuevo_jugador == null or nuevo_jugador == self:
		return
	nuevo_jugador._asignar_control_a_este_jugador()


# ==============================================================================
# INTELIGENCIA ARTIFICIAL TÁCTICA 5v5 (EQUILIBRADA, RÁPIDA Y CON DESMARQUE/MARCAJE)
# ==============================================================================

func _procesar_ia_tactica(delta: float) -> void:
	var nodo_balon: Balon3D = _obtener_balon_juego()
	if nodo_balon == null:
		_direccion_deseada = Vector3.ZERO
		return
	
	var pos_balon: Vector3 = nodo_balon.global_position
	
	# 0. Si este jugador IA es el sacador autorizado o está anclado en saque (banda, córner, meta, centro)
	if _en_posicion_saque or nodo_balon.sacador_autorizado == self:
		_comportamiento_sacador_ia(pos_balon, nodo_balon)
		return
	
	# 1. IA PORTERO
	if posicion_tactica == "PORTERO":
		_comportamiento_portero(delta, pos_balon, nodo_balon)
		return
	
	var portador: Jugador3D = nodo_balon.portador_actual as Jugador3D if nodo_balon.esta_siendo_conducido() else null
	var rival_tiene_balon: bool = portador != null and portador.equipo == Equipo.VISITANTE
	var local_tiene_balon: bool = portador != null and portador.equipo == Equipo.LOCAL
	
	if equipo == Equipo.VISITANTE:
		if portador == self or tiene_posesion:
			_comportamiento_portador_rival(delta, nodo_balon)
		elif rival_tiene_balon:
			_comportamiento_apoyo_ofensivo_rival(pos_balon, nodo_balon)
		else:
			_comportamiento_defensa_rival(delta, pos_balon, nodo_balon)
	else:
		if portador == self or tiene_posesion:
			# En caso de que un jugador local con balón aún no tenga control de usuario, transferir inmediatamente
			_asignar_control_a_este_jugador()
		elif local_tiene_balon:
			_comportamiento_ataque_local(pos_balon, nodo_balon)
		else:
			_comportamiento_defensa_local(delta, pos_balon, nodo_balon)


## Ejecución reglamentaria de saques por parte de la IA: plantado en su sitio sin huir, apunta a un compañero y pasa
func _comportamiento_sacador_ia(_pos_balon: Vector3, balon: Balon3D) -> void:
	sprint_activo = false
	if not tiene_posesion and puede_tomar_balon():
		tomar_posesion(balon)
		_cooldown_decision_ia = 0.45
	
	var dir_campo: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	var mejor_comp: Jugador3D = _buscar_mejor_receptor(dir_campo)
	if mejor_comp != null:
		var hacia_comp: Vector3 = mejor_comp.global_position - global_position
		hacia_comp.y = 0.0
		if hacia_comp.length_squared() > 0.01:
			_direccion_deseada = hacia_comp.normalized()
		else:
			_direccion_deseada = dir_campo
	else:
		_direccion_deseada = dir_campo
	
	if tiene_posesion and _cooldown_decision_ia <= 0.0:
		ejecutar_pase(0.55)


## Comportamiento del portero basado en sus estadísticas individuales (gk_reflejos, gk_estirada, gk_manejo, gk_posicionamiento)
func _comportamiento_portero(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	# Si el portero IA tiene el balón (atrapado o en los pies), distribuir con pase rápido a un compañero
	if tiene_posesion or balon.portador_actual == self:
		_direccion_deseada = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
		sprint_activo = false
		if _cooldown_decision_ia <= 0.0:
			_cooldown_decision_ia = 0.6
			ejecutar_pase(0.55)
		return
	
	var linea_meta_x: float = -19.4 if equipo == Equipo.LOCAL else 19.4
	var dist_al_balon: float = global_position.distance_to(pos_balon)
	var vel_balon: Vector3 = balon.linear_velocity
	var rapidez_tiro: float = vel_balon.length()
	
	var es_tiro_peligroso: bool = false
	if equipo == Equipo.LOCAL and vel_balon.x < -3.8 and pos_balon.x > -19.8:
		es_tiro_peligroso = true
	elif equipo == Equipo.VISITANTE and vel_balon.x > 3.8 and pos_balon.x < 19.8:
		es_tiro_peligroso = true
	
	# 1. INTENTO DE ATAJADA BASADO EN ESTADÍSTICAS DEL PORTERO VS POTENCIA/COLOCACIÓN DEL TIRO
	var es_pase_companero: bool = (balon.ultimo_toque_equipo == int(equipo))
	if es_tiro_peligroso and not es_pase_companero and dist_al_balon < 4.5:
		var limite_cobertura_z: float = 1.15 + (gk_posicionamiento / 99.0) * 0.42
		var intercept_z: float = clampf(pos_balon.z + (vel_balon.z / maxf(0.1, abs(vel_balon.x))) * abs(global_position.x - pos_balon.x), -limite_cobertura_z, limite_cobertura_z)
		var pos_bloqueo: Vector3 = Vector3(global_position.x, 0.0, intercept_z)
		_direccion_deseada = (pos_bloqueo - global_position).normalized()
		sprint_activo = true
		
		# Alcance físico de estirada según gk_estirada (0.72m a 1.14m en un arco de 3.7m de ancho)
		var radio_estirada: float = 0.72 + (gk_estirada / 99.0) * 0.42
		if dist_al_balon < radio_estirada and _tiempo_paradon_reciente <= 0.0:
			_tiempo_paradon_reciente = 1.05
			
			# Dificultad según la potencia (velocidad) y qué tan esquinado o alto va el disparo
			var factor_potencia_tiro: float = clampf((rapidez_tiro - 11.5) / 18.5, 0.05, 0.98)
			var factor_esquina: float = clampf(abs(pos_balon.z) / 1.80, 0.0, 0.42)
			var dificultad_tiro: float = factor_potencia_tiro * 0.72 + factor_esquina * 0.48
			
			var habilidad_portero: float = ((gk_reflejos * 0.55 + gk_estirada * 0.45) / 99.0) * 0.88
			var prob_atajar: float = clampf(0.50 + (habilidad_portero - dificultad_tiro) * 0.85, 0.14, 0.84)
			
			if randf() < prob_atajar:
				var umbral_retencion: float = 13.5 + (gk_manejo / 99.0) * 6.5
				if rapidez_tiro < umbral_retencion and abs(pos_balon.x - linea_meta_x) < 4.5:
					atrapar_con_manos(balon)
					_emitir_anuncio_hud("¡%s ATRAPA EL BALÓN!" % nombre_jugador.to_upper())
				else:
					var dir_desvio_z: float = 1.0 if pos_balon.z >= 0.0 else -1.0
					var impulso_paradon: Vector3 = Vector3(1.2 if equipo == Equipo.LOCAL else -1.2, 0.45, dir_desvio_z * 1.4).normalized() * 8.2
					balon.patear(impulso_paradon, int(equipo))
					_emitir_anuncio_hud("¡PARADÓN DE %s!" % nombre_jugador.to_upper())
		return
	
	# 2. RECEPCIÓN DE PASE ATRÁS O BALÓN SUELTO EN EL ÁREA
	var dentro_area_propia: bool = _esta_en_area_propia(pos_balon)
	if not balon.esta_siendo_conducido() and balon.sacador_autorizado == null and (dentro_area_propia or (es_pase_companero and dist_al_balon < 6.0 and abs(pos_balon.x - linea_meta_x) < 8.0)):
		_direccion_deseada = (pos_balon - global_position).normalized()
		sprint_activo = dist_al_balon > 1.5
		if dist_al_balon < 1.05 and puede_tomar_balon():
			if dentro_area_propia and not es_pase_companero:
				atrapar_con_manos(balon)
			else:
				tomar_posesion(balon)
		return
	
	# 3. ACHIQUE Y POSICIONAMIENTO ANGULAR SEGÚN gk_posicionamiento
	sprint_activo = false
	var factor_pos: float = gk_posicionamiento / 99.0
	var max_z_pos: float = 0.95 + factor_pos * 0.35
	var angulo_z: float = clampf(pos_balon.z * (0.28 + factor_pos * 0.12), -max_z_pos, max_z_pos)
	var avance_x: float = clampf((20.0 - abs(pos_balon.x)) * 0.14, 0.35, 1.75)
	var x_posicionada: float = linea_meta_x + (avance_x if equipo == Equipo.LOCAL else -avance_x)
	
	var pos_deseada: Vector3 = Vector3(x_posicionada, 0.0, angulo_z)
	var delta_pos: Vector3 = pos_deseada - global_position
	_direccion_deseada = delta_pos.normalized() if delta_pos.length() > 0.25 else Vector3.ZERO


## Conducción ágil, evasión de rivales, pases y finalización del portador CPU (Visitante)
func _comportamiento_portador_rival(_delta: float, _balon: Balon3D) -> void:
	var pos_arco_local: Vector3 = Vector3(-20.0, 0.0, 0.0)
	var hacia_arco: Vector3 = pos_arco_local - global_position
	hacia_arco.y = 0.0
	var dist_arco: float = hacia_arco.length()
	var dir_arco: Vector3 = hacia_arco.normalized() if dist_arco > 0.01 else Vector3(-1.0, 0.0, 0.0)
	var presion: float = calcular_presion_rival()
	
	# 1. Decisión de tiro a puerta cuando está en rango ofensivo
	if dist_arco < 14.5 and _cooldown_decision_ia <= 0.0:
		var prob_tiro: float = 0.85 if dist_arco < 9.5 else 0.55
		if randf() < prob_tiro:
			_cooldown_decision_ia = 0.65
			var esquina_z: float = -0.35 if randf() > 0.5 else 0.35
			_direccion_deseada = (dir_arco + Vector3(0.0, 0.0, esquina_z)).normalized()
			ejecutar_tiro(randf_range(0.58, 0.88))
			return
	
	# 2. Decisión de pase o pase al hueco si hay presión o un compañero mejor ubicado en ataque
	if _cooldown_decision_ia <= 0.0:
		var companero_adelantado: Jugador3D = _buscar_mejor_receptor(Vector3(-1.0, 0.0, 0.0))
		var tiene_companero_en_ventaja: bool = companero_adelantado != null and (companero_adelantado.global_position.x < global_position.x - 2.5) and companero_adelantado.calcular_presion_rival() < 0.35
		
		if (presion > 0.38 and randf() < 0.75) or (tiene_companero_en_ventaja and randf() < 0.45):
			_cooldown_decision_ia = 0.55
			if tiene_companero_en_ventaja and randf() < 0.55:
				ejecutar_pase_hueco(randf_range(0.45, 0.75))
			else:
				ejecutar_pase(randf_range(0.45, 0.75))
			return
		else:
			_cooldown_decision_ia = 0.35
	
	# 3. Conducción ofensiva hacia el arco local esquivando defensores
	var vector_evasion: Vector3 = Vector3.ZERO
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	for n: Node in locales:
		var def_local: Jugador3D = n as Jugador3D
		if def_local and def_local.posicion_tactica != "PORTERO":
			var diff_def: Vector3 = global_position - def_local.global_position
			diff_def.y = 0.0
			var d_def: float = diff_def.length()
			if d_def < 3.4 and d_def > 0.01:
				var dir_escape: Vector3 = diff_def.normalized()
				dir_escape.x = minf(dir_escape.x, -0.2)
				vector_evasion += dir_escape * ((3.4 - d_def) / 3.4) * 1.1
	
	var dir_conduccion: Vector3 = (dir_arco + vector_evasion).normalized()
	if abs(global_position.z) > 8.2:
		dir_conduccion.z = -signf(global_position.z) * 0.5
		dir_conduccion = dir_conduccion.normalized()
	
	_direccion_deseada = dir_conduccion
	sprint_activo = (presion < 0.55)


## Calcula la posición de desmarque dinámico buscando huecos lejos de los defensores rivales
func _calcular_posicion_desmarque_ofensivo(pos_balon: Vector3, es_equipo_local: bool) -> Vector3:
	var dir_ataque: float = 1.0 if es_equipo_local else -1.0
	var pos_objetivo: Vector3 = _posicion_tactica_inicial
	
	if posicion_tactica == "PIVOT":
		var x_piv: float = clampf(pos_balon.x + dir_ataque * 6.5, -16.5, 16.5)
		var z_piv: float = clampf(-pos_balon.z * 0.45, -4.5, 4.5)
		pos_objetivo = Vector3(x_piv, 0.0, z_piv)
	elif posicion_tactica == "ALA_IZQ":
		var x_ala_i: float = clampf(pos_balon.x + dir_ataque * 4.2, -16.0, 16.0)
		var en_zona_final: bool = (es_equipo_local and x_ala_i > 11.0) or (not es_equipo_local and x_ala_i < -11.0)
		var z_ala_i: float = -4.6 if en_zona_final else -6.8
		pos_objetivo = Vector3(x_ala_i, 0.0, z_ala_i)
	elif posicion_tactica == "ALA_DER":
		var x_ala_d: float = clampf(pos_balon.x + dir_ataque * 4.2, -16.0, 16.0)
		var en_zona_final_d: bool = (es_equipo_local and x_ala_d > 11.0) or (not es_equipo_local and x_ala_d < -11.0)
		var z_ala_d: float = 4.6 if en_zona_final_d else 6.8
		pos_objetivo = Vector3(x_ala_d, 0.0, z_ala_d)
	elif posicion_tactica == "CIERRE":
		var x_cie: float = clampf(pos_balon.x - dir_ataque * 5.2, -15.5, 15.5)
		var z_cie: float = clampf(pos_balon.z * 0.35, -4.5, 4.5)
		pos_objetivo = Vector3(x_cie, 0.0, z_cie)
	
	# Desmarque activo: desplazarse fuera de la marca del defensor más cercano
	var grupo_rivales: String = "equipo_visitante" if es_equipo_local else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rivales)
	var offset_desmarque: Vector3 = Vector3.ZERO
	
	for n: Node in rivales:
		var def_rival: Jugador3D = n as Jugador3D
		if def_rival and def_rival.posicion_tactica != "PORTERO":
			var diff_r: Vector3 = pos_objetivo - def_rival.global_position
			diff_r.y = 0.0
			var d_r: float = diff_r.length()
			if d_r < 3.2 and d_r > 0.01:
				offset_desmarque += diff_r.normalized() * ((3.2 - d_r) / 3.2) * 2.2
	
	pos_objetivo += offset_desmarque
	pos_objetivo.x = clampf(pos_objetivo.x, -17.5, 17.5)
	pos_objetivo.z = clampf(pos_objetivo.z, -8.5, 8.5)
	return pos_objetivo


## Apoyo ofensivo y desmarque del equipo visitante (CPU en ataque)
func _comportamiento_apoyo_ofensivo_rival(pos_balon: Vector3, _balon: Balon3D) -> void:
	_estado_ia = EstadoIA.DESMARQUE_APOYO
	var pos_objetivo: Vector3 = _calcular_posicion_desmarque_ofensivo(pos_balon, false)
	
	var delta_pos: Vector3 = pos_objetivo - global_position
	delta_pos.y = 0.0
	if delta_pos.length() > 0.55:
		_direccion_deseada = delta_pos.normalized()
		sprint_activo = delta_pos.length() > 2.2
	else:
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false


## Ataque y desmarque inteligente de compañeros del equipo local
func _comportamiento_ataque_local(pos_balon: Vector3, _balon: Balon3D) -> void:
	_estado_ia = EstadoIA.DESMARQUE_APOYO
	var pos_desmarque: Vector3 = _calcular_posicion_desmarque_ofensivo(pos_balon, true)
	
	var delta_desmarque: Vector3 = pos_desmarque - global_position
	delta_desmarque.y = 0.0
	if delta_desmarque.length() > 0.55:
		_direccion_deseada = delta_desmarque.normalized()
		sprint_activo = delta_desmarque.length() > 2.2
	else:
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false


## Calcula la posición de marcaje individual (entre el atacante rival asignado y el arco propio)
func _calcular_posicion_marcaje_defensivo(pos_balon: Vector3, es_equipo_local: bool) -> Vector3:
	var grupo_atacantes: String = "equipo_visitante" if es_equipo_local else "equipo_local"
	var atacantes: Array[Node] = get_tree().get_nodes_in_group(grupo_atacantes)
	var arco_propio: Vector3 = Vector3(-20.0 if es_equipo_local else 20.0, 0.0, 0.0)
	
	var rol_objetivo: String = posicion_tactica
	if posicion_tactica == "ALA_IZQ":
		rol_objetivo = "ALA_DER"
	elif posicion_tactica == "ALA_DER":
		rol_objetivo = "ALA_IZQ"
	elif posicion_tactica == "CIERRE":
		rol_objetivo = "PIVOT"
	elif posicion_tactica == "PIVOT":
		rol_objetivo = "CIERRE"
	
	var atacante_asignado: Jugador3D = null
	var mejor_dist: float = 999.0
	
	for n: Node in atacantes:
		var atq: Jugador3D = n as Jugador3D
		if atq == null or atq.posicion_tactica == "PORTERO" or atq.tiene_posesion:
			continue
		if atq.posicion_tactica == rol_objetivo:
			atacante_asignado = atq
			break
		var d: float = _posicion_tactica_inicial.distance_to(atq.global_position)
		if d < mejor_dist:
			mejor_dist = d
			atacante_asignado = atq
	
	if atacante_asignado != null:
		var pos_atq: Vector3 = atacante_asignado.global_position
		var dir_arco: Vector3 = (arco_propio - pos_atq).normalized()
		var dir_balon: Vector3 = (pos_balon - pos_atq).normalized()
		var pos_marca: Vector3 = pos_atq + (dir_arco * 1.45 + dir_balon * 0.55)
		pos_marca.x = clampf(pos_marca.x, -18.0, 18.0)
		pos_marca.z = clampf(pos_marca.z, -8.8, 8.8)
		return pos_marca
	
	var pos_zonal: Vector3 = _posicion_tactica_inicial
	if es_equipo_local:
		pos_zonal.x = clampf(pos_zonal.x + (pos_balon.x + 10.0) * 0.38, -16.5, 2.0)
	else:
		pos_zonal.x = clampf(pos_zonal.x + (pos_balon.x - 10.0) * 0.38, -2.0, 16.5)
	pos_zonal.z = clampf(pos_zonal.z + pos_balon.z * 0.35, -7.8, 7.8)
	return pos_zonal


## Defensa inteligente del rival (recuperación directa de balón suelto, presión al portador y marcaje al hombre)
func _comportamiento_defensa_rival(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	var rivales_campo: Array[Node] = get_tree().get_nodes_in_group("equipo_visitante")
	var mas_cercano: Jugador3D = null
	var min_dist: float = 999.0
	
	for nodo: Node in rivales_campo:
		var jug: Jugador3D = nodo as Jugador3D
		if jug and jug.posicion_tactica != "PORTERO":
			var d: float = jug.global_position.distance_to(pos_balon)
			if d < min_dist:
				min_dist = d
				mas_cercano = jug
	
	# CASO A: Balón libre en juego -> el jugador más cercano corre directo al balón
	if not balon.esta_siendo_conducido():
		if mas_cercano == self and balon.sacador_autorizado == null:
			_estado_ia = EstadoIA.PRESIÓN
			var hacia_balon: Vector3 = pos_balon - global_position
			hacia_balon.y = 0.0
			_direccion_deseada = hacia_balon.normalized() if hacia_balon.length_squared() > 0.01 else Vector3.ZERO
			sprint_activo = true
			return
		else:
			_estado_ia = EstadoIA.COBERTURA
			var pos_marca_libre: Vector3 = _calcular_posicion_marcaje_defensivo(pos_balon, false)
			var delta_l: Vector3 = pos_marca_libre - global_position
			delta_l.y = 0.0
			_direccion_deseada = delta_l.normalized() if delta_l.length() > 0.45 else Vector3.ZERO
			sprint_activo = delta_l.length() > 3.0
			return
	
	# CASO B: El equipo local conduce el balón -> si el portador está en saque reglamentario, mantener distancia
	var portador: Jugador3D = balon.portador_actual as Jugador3D
	if portador != null and (portador._en_posicion_saque or balon.sacador_autorizado == portador):
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false
		return
	
	if mas_cercano == self:
		_estado_ia = EstadoIA.PRESIÓN
		var P: Vector3 = portador.global_position if portador != null else pos_balon
		var G: Vector3 = Vector3(20.0, 0.0, 0.0)
		var dir_GP: Vector3 = (G - P).normalized()
		
		var dist_objetivo: float = 0.95 if (portador != null and portador.puede_ser_robado() and _cooldown_intento_robo <= 0.0) else radio_contencion
		var T: Vector3 = P + dir_GP * dist_objetivo
		
		var hacia_T: Vector3 = T - global_position
		hacia_T.y = 0.0
		var dist_self_T: float = hacia_T.length()
		
		if dist_self_T > 0.28:
			_direccion_deseada = hacia_T.normalized()
		else:
			_direccion_deseada = Vector3.ZERO
		
		var dist_self_P: float = global_position.distance_to(P)
		if dist_self_P < dist_objetivo:
			var hacia_P: Vector3 = P - global_position
			hacia_P.y = 0.0
			if hacia_P.length_squared() > 0.001:
				var dir_P: Vector3 = hacia_P.normalized()
				var comp_radial: float = _direccion_deseada.dot(dir_P)
				if comp_radial > 0.0:
					_direccion_deseada -= dir_P * comp_radial
		
		sprint_activo = (dist_self_T > 1.8)
		
		if dist_self_P < 1.25 and _cooldown_intento_robo <= 0.0:
			if portador and portador.equipo == Equipo.LOCAL:
				_intentar_robo(portador, balon)
	else:
		_estado_ia = EstadoIA.COBERTURA
		var pos_objetivo: Vector3 = _calcular_posicion_marcaje_defensivo(pos_balon, false)
		var delta_pos: Vector3 = pos_objetivo - global_position
		delta_pos.y = 0.0
		_direccion_deseada = delta_pos.normalized() if delta_pos.length() > 0.45 else Vector3.ZERO
		sprint_activo = delta_pos.length() > 2.8


## Defensa inteligente de compañeros del equipo local (recuperación de balón suelto y marcaje al hombre)
func _comportamiento_defensa_local(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	var dist_balon: float = global_position.distance_to(pos_balon)
	
	# Si el rival está ejecutando un saque reglamentario, no invadir ni perseguir hasta que el balón se juegue
	var portador_actual: Jugador3D = balon.portador_actual as Jugador3D if balon.esta_siendo_conducido() else null
	if balon.sacador_autorizado != null or (portador_actual != null and portador_actual._en_posicion_saque):
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false
		return
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var ia_mas_cercano: Jugador3D = null
	var min_d: float = 999.0
	for n: Node in locales:
		var j_loc: Jugador3D = n as Jugador3D
		if j_loc and not j_loc.es_controlado and j_loc.posicion_tactica != "PORTERO":
			var d: float = j_loc.global_position.distance_to(pos_balon)
			if d < min_d:
				min_d = d
				ia_mas_cercano = j_loc
	
	if _orden_presion_equipo or (not balon.esta_siendo_conducido() and balon.sacador_autorizado == null and (ia_mas_cercano == self or dist_balon < 5.0)):
		var hacia_b: Vector3 = pos_balon - global_position
		hacia_b.y = 0.0
		_direccion_deseada = hacia_b.normalized() if hacia_b.length_squared() > 0.01 else Vector3.ZERO
		sprint_activo = true
		if dist_balon < 1.25:
			_orden_presion_equipo = false
			if balon.esta_siendo_conducido() and _cooldown_intento_robo <= 0.0:
				var portador_vis: Jugador3D = balon.portador_actual as Jugador3D
				if portador_vis and portador_vis.equipo == Equipo.VISITANTE:
					_intentar_robo(portador_vis, balon)
	else:
		var pos_marca: Vector3 = _calcular_posicion_marcaje_defensivo(pos_balon, true)
		var delta_pos: Vector3 = pos_marca - global_position
		delta_pos.y = 0.0
		_direccion_deseada = delta_pos.normalized() if delta_pos.length() > 0.45 else Vector3.ZERO
		sprint_activo = delta_pos.length() > 2.8


func _obtener_balon_juego() -> Balon3D:
	if _balon_referencia != null and is_instance_valid(_balon_referencia):
		return _balon_referencia
	var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
	if not balones.is_empty():
		return balones[0] as Balon3D
	return null


## Calcula el empuje de separación entre jugadores para evitar colisiones y superposiciones
func _calcular_separacion() -> Vector3:
	if es_controlado or _en_posicion_saque:
		return Vector3.ZERO
	
	var empuje: Vector3 = Vector3.ZERO
	var todos_jugadores: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	
	for nodo: Node in todos_jugadores:
		if nodo == self or not (nodo is Jugador3D):
			continue
		var otro: Jugador3D = nodo as Jugador3D
		var diff: Vector3 = global_position - otro.global_position
		diff.y = 0.0
		var d: float = diff.length()
		
		if d < radio_separacion and d > 0.0001:
			var peso: float = 1.0 if otro.es_controlado else 0.5
			var magnitud: float = ((radio_separacion - d) / radio_separacion) * fuerza_separacion * peso
			empuje += diff.normalized() * magnitud
	
	return empuje


func _aplicar_movimiento(delta: float) -> void:
	# Si el jugador está ejecutando un saque reglamentario, NO puede caminar ni desplazarse, solo rotar para apuntar
	if _en_posicion_saque:
		global_position = _pos_anclaje_saque
		velocity = Vector3.ZERO
		if _direccion_deseada.length_squared() > 0.01:
			var angulo_apuntado: float = atan2(-_direccion_deseada.x, -_direccion_deseada.z)
			rotation.y = lerp_angle(rotation.y, angulo_apuntado, clampf(velocidad_giro * delta, 0.0, 1.0))
		return
	
	# Velocidad calibrada para un ritmo de partido táctico, realista y totalmente controlable
	var vel_base: float = 3.85 + (vel_movimiento / 99.0) * 1.75
	var acel_base: float = 26.0 + (vel_movimiento / 99.0) * 10.0
	var vel_max_efectiva: float = vel_base * (multiplicador_sprint if sprint_activo else 1.0)
	
	# Solo reducir velocidad si el jugador está aturdido tras fallar una barrida
	if _t_aturdimiento > 0.0:
		vel_max_efectiva *= 0.35
	
	var vel_horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	
	if _direccion_deseada.length_squared() > 0.01:
		var vel_objetivo: Vector3 = _direccion_deseada * vel_max_efectiva
		vel_horizontal = vel_horizontal.move_toward(vel_objetivo, acel_base * delta)
		
		var angulo_objetivo: float = atan2(-_direccion_deseada.x, -_direccion_deseada.z)
		rotation.y = lerp_angle(rotation.y, angulo_objetivo, clampf(velocidad_giro * delta, 0.0, 1.0))
	else:
		vel_horizontal = vel_horizontal.move_toward(Vector3.ZERO, 30.0 * delta)
	
	var empuje_sep: Vector3 = _calcular_separacion()
	vel_horizontal += empuje_sep
	
	var vel_max_clamp: float = vel_max_efectiva * 1.08
	if vel_horizontal.length() > vel_max_clamp:
		vel_horizontal = vel_horizontal.normalized() * vel_max_clamp
	
	velocity.x = vel_horizontal.x
	velocity.z = vel_horizontal.z


## Animación procedural de extremidades (brazos, piernas, zancada al correr, patada y barrida)
func _animar_extremidades(delta: float) -> void:
	if pivote_pierna_izq == null or pivote_pierna_der == null or pivote_brazo_izq == null or pivote_brazo_der == null:
		return
	
	var vel_plana: float = Vector2(velocity.x, velocity.z).length()
	
	# 1. Pose de barrida deslizante
	if _en_barrida:
		pivote_pierna_der.rotation.x = lerpf(pivote_pierna_der.rotation.x, 1.15, delta * 18.0)
		pivote_pierna_izq.rotation.x = lerpf(pivote_pierna_izq.rotation.x, -0.55, delta * 18.0)
		pivote_brazo_izq.rotation.x = lerpf(pivote_brazo_izq.rotation.x, -0.7, delta * 18.0)
		pivote_brazo_der.rotation.x = lerpf(pivote_brazo_der.rotation.x, -0.7, delta * 18.0)
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.42, delta * 16.0)
			visual.position.y = lerpf(visual.position.y, -0.18, delta * 16.0)
		return
	
	# 2. Animación de patada (tiro / pase)
	if _t_anim_patada > 0.0:
		var fase_patada: float = sin((_t_anim_patada / 0.28) * PI)
		pivote_pierna_der.rotation.x = fase_patada * 1.25
		pivote_pierna_izq.rotation.x = -fase_patada * 0.35
		pivote_brazo_izq.rotation.x = fase_patada * 0.75
		pivote_brazo_der.rotation.x = -fase_patada * 0.55
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.08 * fase_patada, delta * 15.0)
			visual.position.y = lerpf(visual.position.y, 0.0, delta * 15.0)
		return
	
	# 3. Ciclo de carrera / conducción vs reposo
	if vel_plana > 0.2 and not _en_posicion_saque:
		var frec_zancada: float = 5.5 + vel_plana * 2.1
		_fase_carrera = fmod(_fase_carrera + delta * frec_zancada, TAU)
		var onda: float = sin(_fase_carrera)
		var amp_pierna: float = clampf(0.25 + vel_plana * 0.11, 0.25, 0.92)
		var amp_brazo: float = amp_pierna * 0.78
		
		pivote_pierna_izq.rotation.x = onda * amp_pierna
		pivote_pierna_der.rotation.x = -onda * amp_pierna
		
		if tiene_balon_en_manos:
			pivote_brazo_izq.rotation.x = lerpf(pivote_brazo_izq.rotation.x, 1.05, delta * 12.0)
			pivote_brazo_der.rotation.x = lerpf(pivote_brazo_der.rotation.x, 1.05, delta * 12.0)
		else:
			pivote_brazo_izq.rotation.x = -onda * amp_brazo
			pivote_brazo_der.rotation.x = onda * amp_brazo
		
		if visual:
			var inclinacion_carrera: float = -0.09 if sprint_activo else -0.05
			visual.rotation.x = lerpf(visual.rotation.x, inclinacion_carrera, delta * 10.0)
			visual.position.y = abs(cos(_fase_carrera)) * 0.038
	else:
		pivote_pierna_izq.rotation.x = lerpf(pivote_pierna_izq.rotation.x, 0.0, delta * 12.0)
		pivote_pierna_der.rotation.x = lerpf(pivote_pierna_der.rotation.x, 0.0, delta * 12.0)
		if tiene_balon_en_manos:
			pivote_brazo_izq.rotation.x = lerpf(pivote_brazo_izq.rotation.x, 1.05, delta * 12.0)
			pivote_brazo_der.rotation.x = lerpf(pivote_brazo_der.rotation.x, 1.05, delta * 12.0)
		else:
			pivote_brazo_izq.rotation.x = lerpf(pivote_brazo_izq.rotation.x, 0.0, delta * 12.0)
			pivote_brazo_der.rotation.x = lerpf(pivote_brazo_der.rotation.x, 0.0, delta * 12.0)
		
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.0, delta * 12.0)
			visual.position.y = lerpf(visual.position.y, 0.0, delta * 12.0)


func get_media_ovr() -> int:
	if posicion_tactica == "PORTERO":
		var media_gk: float = (
			gk_estirada * 0.24 +
			gk_reflejos * 0.28 +
			gk_manejo * 0.18 +
			gk_posicionamiento * 0.20 +
			gk_saque * 0.10
		)
		return int(round(media_gk))
	
	var suma_ponderada: float = (
		vel_movimiento * 0.22 +
		potencia_tiro * 0.20 +
		precision_tiro * 0.20 +
		vision_pase * 0.18 +
		control_balon * 0.20
	)
	return int(round(suma_ponderada))


func establecer_sprint(activo: bool) -> void:
	_sprint_tactil_mantenido = activo
	sprint_activo = activo


func establecer_direccion_virtual(dir: Vector2) -> void:
	direccion_virtual = dir


func _emitir_anuncio_hud(texto: String) -> void:
	var hud: HUDPartido = get_tree().get_first_node_in_group("hud_partido") as HUDPartido
	if hud and is_instance_valid(hud):
		hud.mostrar_anuncio(texto)


func _actualizar_colores_uniforme() -> void:
	if torso_mesh == null:
		return
	
	var es_loc: bool = (equipo == Equipo.LOCAL)
	var info_eq: Dictionary = Futsal_3D.obtener_info_equipo(es_loc)
	
	var col_camiseta: Color = Color(0.85, 0.15, 0.15) if es_loc else Color(0.95, 0.85, 0.1)
	var col_escudo: Color = Color(0.95, 0.8, 0.2) if es_loc else Color(0.12, 0.3, 0.65)
	var col_short: Color = Color(0.1, 0.12, 0.18) if es_loc else Color(0.08, 0.14, 0.24)
	
	if not info_eq.is_empty():
		col_camiseta = Color.from_string(str(info_eq.get("color_primario", "")), col_camiseta)
		col_escudo = Color.from_string(str(info_eq.get("color_secundario", "")), col_escudo)
		col_short = Color.from_string(str(info_eq.get("color_short", "")), col_short)
	
	if posicion_tactica == "PORTERO":
		var hex_gk: String = str(info_eq.get("color_arquero", ""))
		col_camiseta = Color.from_string(hex_gk, Color(0.1, 0.75, 0.25) if es_loc else Color(0.95, 0.45, 0.1))
	
	var mat_torso: StandardMaterial3D = StandardMaterial3D.new()
	mat_torso.roughness = 0.42
	mat_torso.albedo_color = col_camiseta
	torso_mesh.material_override = mat_torso
	
	if manga_izq_mesh:
		manga_izq_mesh.material_override = mat_torso
	if manga_der_mesh:
		manga_der_mesh.material_override = mat_torso
	if media_izq_mesh:
		media_izq_mesh.material_override = mat_torso
	if media_der_mesh:
		media_der_mesh.material_override = mat_torso
	
	var mat_short: StandardMaterial3D = StandardMaterial3D.new()
	mat_short.roughness = 0.55
	mat_short.albedo_color = col_short
	if pantalones_mesh:
		pantalones_mesh.material_override = mat_short
	if muslo_izq_mesh:
		muslo_izq_mesh.material_override = mat_short
	if muslo_der_mesh:
		muslo_der_mesh.material_override = mat_short
	
	if escudo_pecho:
		var mat_escudo: StandardMaterial3D = StandardMaterial3D.new()
		mat_escudo.roughness = 0.25
		mat_escudo.albedo_color = col_escudo
		escudo_pecho.material_override = mat_escudo
	
	if posicion_tactica == "PORTERO":
		var mat_guantes: StandardMaterial3D = StandardMaterial3D.new()
		mat_guantes.roughness = 0.35
		mat_guantes.albedo_color = Color(0.95, 0.96, 0.98)
		if mano_izq_mesh:
			mano_izq_mesh.material_override = mat_guantes
		if mano_der_mesh:
			mano_der_mesh.material_override = mat_guantes

