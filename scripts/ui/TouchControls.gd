class_name TouchControls
extends Control

## Módulo desacoplado de Controles Táctiles Dinámicos (Ataque vs. Defensa) y Gestos Swipe/Flick
## inspirado en FC Mobile y eFootball para Futsal_3D (Godot 4 Compatibility / GLES3).
##
## 1. Máquina de Estados de la UI conectada a `GestorPartido.posesion_cambiada`:
##    - MODO POSESIÓN (ATAQUE):
##      * Botón 1 (BotonPase):   PASE (Raso al pie / Swipe Up: Pase Elevado - Sombrerito)
##      * Botón 2 (BotonHueco):  HUECO (Pase filtrado con IA de conos de pase entre líneas)
##      * Botón 3 (BotonTiro):   TIRO (Normal potente / Swipe Down: Tiro Colocado Magnus / Swipe Up: Vaselina)
##      * Botón 4 (BotonSprint): ESPRINTAR (Aceleración en conducción)
##    - MODO SIN BALÓN (DEFENSA):
##      * Botón 1 (BotonPase):   CAMBIAR (Cambia al defensor más cercano al balón o línea de pase)
##      * Botón 2 (BotonHueco):  PRESIÓN 2° DEF (Ordena a un compañero IA presionar al portador)
##      * Botón 3 (BotonTiro):   ENTRADA / BARRIDA (Tackle defensivo o intercepción de pierna)
##      * Botón 4 (BotonSprint): ESPRINTAR + PRESIÓN (Carrera rápida de cierre hacia el balón)
##
## 2. Detección de Gestos Multitáctiles (`InputEventScreenTouch` y `InputEventScreenDrag`):
##    - Soporta deslizamiento vertical en BotonTiro (▲ Vaselina / ▼ Colocado) y BotonPase (▲ Elevado)
##      con indicadores de flechas sutiles y retroalimentación visual en tiempo real.

enum ModoHUD {
	ATAQUE = 0,
	DEFENSA = 1,
	SAQUE_PIE = 2,
	SAQUE_MANO = 3
}

@export var ruta_jugador: NodePath = ^"../../Jugadores/Local_Pivot"
@export var umbral_swipe_px: float = 28.0
@export var velocidad_carga_potencia: float = 1.65

# Referencias a nodos del Joystick Virtual
@onready var joystick_base: Control = $JoystickBase
@onready var joystick_pomo: Panel = $JoystickBase/Pomo

# Referencias a los 4 botones de acción contextuales
@onready var btn_pase: Button = $BotonesAccion/BotonPase
@onready var btn_hueco: Button = $BotonesAccion/BotonHueco
@onready var btn_tiro: Button = $BotonesAccion/BotonTiro
@onready var btn_sprint: Button = $BotonesAccion/BotonSprint

# Indicadores sutiles de flechas Swipe (definidos en escena .tscn)
@onready var label_flecha_tiro_up: Label = get_node_or_null("BotonesAccion/BotonTiro/FlechaUpTiro") as Label
@onready var label_flecha_tiro_down: Label = get_node_or_null("BotonesAccion/BotonTiro/FlechaDownTiro") as Label
@onready var label_flecha_pase_up: Label = get_node_or_null("BotonesAccion/BotonPase/FlechaUpPase") as Label
@onready var label_gesto_activo: Label = get_node_or_null("BotonesAccion/LabelGestoActivo") as Label

# Barra de carga de potencia y gesto
@onready var barra_potencia: ProgressBar = $BarraPotencia

# Referencias de estado y partido
var _jugador_referencia: Jugador3D = null
var _gestor_partido: GestorPartido = null
var _modo_actual: int = -1
var _modo_defensivo_actual: bool = false

# Estado multitáctil del Joystick
var _tocando_joystick: bool = false
var _joystick_touch_id: int = -1
var _radio_maximo_joystick: float = 65.0
var _centro_joystick: Vector2 = Vector2.ZERO
var _direccion_joystick_actual: Vector2 = Vector2.ZERO

# Estado multitáctil y Swipe/Flick en botones de acción
var _tiro_touch_id: int = -1
var _tiro_pos_inicial: Vector2 = Vector2.ZERO
var _gesto_tiro_detectado: int = Jugador3D.TipoTiro.NORMAL
var _tiro_mouse_activo: bool = false

var _pase_touch_id: int = -1
var _pase_pos_inicial: Vector2 = Vector2.ZERO
var _gesto_pase_detectado: int = Jugador3D.TipoPase.RASO
var _pase_mouse_activo: bool = false

var _hueco_touch_id: int = -1
var _sprint_touch_id: int = -1

# Carga de potencia progresiva
var _accion_cargando: String = "" # "TIRO", "PASE", "HUECO"
var _potencia_acumulada: float = 0.0
var _tecla_espacio_mantenida: bool = false
var _tecla_x_mantenida: bool = false
var _tecla_c_mantenida: bool = false

# Estilos dinámicos (StyleBoxFlat) para transición visual Ataque vs. Defensa
var _style_pase_ataque: StyleBoxFlat
var _style_pase_defensa: StyleBoxFlat
var _style_hueco_ataque: StyleBoxFlat
var _style_hueco_defensa: StyleBoxFlat
var _style_tiro_ataque: StyleBoxFlat
var _style_tiro_defensa: StyleBoxFlat
var _style_sprint_ataque: StyleBoxFlat
var _style_sprint_defensa: StyleBoxFlat


func _ready() -> void:
	_inicializar_estilos_botones()
	_conectar_botones_respaldo()
	_conectar_gestor_partido()
	
	if joystick_base:
		_centro_joystick = joystick_base.size * 0.5
		_resetear_joystick()
	if barra_potencia:
		barra_potencia.visible = false
	if label_gesto_activo:
		label_gesto_activo.visible = false
	
	_aplicar_modo_hud(ModoHUD.ATAQUE)


func _process(delta: float) -> void:
	_procesar_carga_potencia(delta)
	_procesar_input_teclado()


func _physics_process(_delta: float) -> void:
	if _tocando_joystick:
		var jug_joy: Jugador3D = obtener_jugador_activo()
		if jug_joy and is_instance_valid(jug_joy):
			jug_joy.establecer_direccion_virtual(_direccion_joystick_actual)
	_sincronizar_estado_contexto_hud()


# ==============================================================================
# 1. MÁQUINA DE ESTADOS DEL HUD TÁCTIL (ATAQUE VS. DEFENSA)
# ==============================================================================

func _conectar_gestor_partido() -> void:
	_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	if _gestor_partido and not _gestor_partido.posesion_cambiada.is_connected(_on_posesion_cambiada):
		_gestor_partido.posesion_cambiada.connect(_on_posesion_cambiada)


func _on_posesion_cambiada(en_ataque_local: bool, _equipo_poseedor: int) -> void:
	var jugador: Jugador3D = obtener_jugador_activo()
	var en_saque_centro: bool = (_gestor_partido != null and _gestor_partido.es_saque_centro_activo())
	
	if jugador and is_instance_valid(jugador) and jugador.tiene_balon_en_manos:
		_aplicar_modo_hud(ModoHUD.SAQUE_MANO)
	elif jugador and is_instance_valid(jugador) and (jugador._en_posicion_saque or en_saque_centro):
		_aplicar_modo_hud(ModoHUD.SAQUE_PIE)
	elif en_ataque_local:
		_aplicar_modo_hud(ModoHUD.ATAQUE)
	else:
		_aplicar_modo_hud(ModoHUD.DEFENSA)


func _sincronizar_estado_contexto_hud() -> void:
	if _gestor_partido == null:
		_conectar_gestor_partido()
	
	var jugador: Jugador3D = obtener_jugador_activo()
	var en_saque_centro: bool = (_gestor_partido != null and _gestor_partido.es_saque_centro_activo())
	
	if jugador and is_instance_valid(jugador) and jugador.tiene_balon_en_manos:
		_aplicar_modo_hud(ModoHUD.SAQUE_MANO)
		return
	if jugador and is_instance_valid(jugador) and (jugador._en_posicion_saque or en_saque_centro):
		_aplicar_modo_hud(ModoHUD.SAQUE_PIE)
		return
	
	var en_ataque: bool = true
	if _gestor_partido != null:
		en_ataque = _gestor_partido.es_ataque_local()
	else:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			var balon: Balon3D = balones[0] as Balon3D
			if balon and is_instance_valid(balon):
				if balon.esta_siendo_conducido() and balon.portador_actual != null:
					var portador: Jugador3D = balon.portador_actual as Jugador3D
					if portador and portador.equipo == Jugador3D.Equipo.VISITANTE:
						en_ataque = false
				elif jugador and jugador.global_position.distance_to(balon.global_position) > 2.6:
					en_ataque = false
	
	_aplicar_modo_hud(ModoHUD.ATAQUE if en_ataque else ModoHUD.DEFENSA)


func _aplicar_modo_hud(nuevo_modo: int) -> void:
	if nuevo_modo == _modo_actual:
		return
	
	_modo_actual = nuevo_modo
	_modo_defensivo_actual = (nuevo_modo == ModoHUD.DEFENSA)
	
	# Si cambiamos a defensa mientras se cargaba una acción ofensiva, cancelar carga
	if _modo_defensivo_actual and _accion_cargando != "":
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		if barra_potencia:
			barra_potencia.visible = false
	
	var mostrar_flechas_swipe: bool = (nuevo_modo == ModoHUD.ATAQUE or nuevo_modo == ModoHUD.SAQUE_PIE)
	if label_flecha_tiro_up:
		label_flecha_tiro_up.visible = (nuevo_modo == ModoHUD.ATAQUE)
	if label_flecha_tiro_down:
		label_flecha_tiro_down.visible = (nuevo_modo == ModoHUD.ATAQUE)
	if label_flecha_pase_up:
		label_flecha_pase_up.visible = mostrar_flechas_swipe
	
	match nuevo_modo:
		ModoHUD.ATAQUE:
			# Modo Posesión (Ataque)
			btn_pase.text = "PASE"
			btn_hueco.text = "HUECO"
			btn_tiro.text = "TIRO"
			btn_sprint.text = "ESPRINTAR"
			_asignar_estilo_boton(btn_pase, _style_pase_ataque)
			_asignar_estilo_boton(btn_hueco, _style_hueco_ataque)
			_asignar_estilo_boton(btn_tiro, _style_tiro_ataque)
			_asignar_estilo_boton(btn_sprint, _style_sprint_ataque)
		
		ModoHUD.DEFENSA:
			# Modo Sin Balón (Defensa)
			btn_pase.text = "CAMBIAR"
			btn_hueco.text = "PRESIÓN\n2° DEF"
			btn_tiro.text = "ENTRADA /\nBARRIDA"
			btn_sprint.text = "ESPRINTAR\n+ PRESIÓN"
			_asignar_estilo_boton(btn_pase, _style_pase_defensa)
			_asignar_estilo_boton(btn_hueco, _style_hueco_defensa)
			_asignar_estilo_boton(btn_tiro, _style_tiro_defensa)
			_asignar_estilo_boton(btn_sprint, _style_sprint_defensa)
		
		ModoHUD.SAQUE_PIE:
			var en_saque_centro: bool = (_gestor_partido != null and _gestor_partido.es_saque_centro_activo())
			btn_pase.text = "PASE"
			btn_hueco.text = "HUECO"
			btn_tiro.text = "PASE CORTO" if en_saque_centro else "TIRO / DESP"
			btn_sprint.text = "FIJO"
			_asignar_estilo_boton(btn_pase, _style_pase_ataque)
			_asignar_estilo_boton(btn_hueco, _style_hueco_ataque)
			_asignar_estilo_boton(btn_tiro, _style_tiro_ataque)
			_asignar_estilo_boton(btn_sprint, _style_sprint_ataque)
		
		ModoHUD.SAQUE_MANO:
			btn_pase.text = "SAQUE MANO"
			btn_hueco.text = "MANO HUECO"
			btn_tiro.text = "LARGO MANO"
			btn_sprint.text = "ÁREA"
			_asignar_estilo_boton(btn_pase, _style_pase_ataque)
			_asignar_estilo_boton(btn_hueco, _style_hueco_ataque)
			_asignar_estilo_boton(btn_tiro, _style_tiro_ataque)
			_asignar_estilo_boton(btn_sprint, _style_sprint_ataque)


func _inicializar_estilos_botones() -> void:
	# Estilos de Ataque (Posesión)
	_style_pase_ataque = _crear_estilo_circular(Color(0.15, 0.60, 0.92, 0.92), Color(0.60, 0.85, 1.0, 0.85), 43)
	_style_hueco_ataque = _crear_estilo_circular(Color(0.12, 0.76, 0.42, 0.92), Color(0.60, 1.0, 0.75, 0.85), 38)
	_style_tiro_ataque = _crear_estilo_circular(Color(0.92, 0.22, 0.22, 0.92), Color(1.0, 0.62, 0.62, 0.85), 48)
	_style_sprint_ataque = _crear_estilo_circular(Color(0.95, 0.72, 0.12, 0.92), Color(1.0, 0.90, 0.60, 0.85), 36)
	
	# Estilos de Defensa (Sin Balón - Colores diferenciados tácticos)
	_style_pase_defensa = _crear_estilo_circular(Color(0.20, 0.42, 0.82, 0.92), Color(0.62, 0.80, 1.0, 0.85), 43)
	_style_hueco_defensa = _crear_estilo_circular(Color(0.56, 0.24, 0.78, 0.92), Color(0.84, 0.65, 1.0, 0.85), 38)
	_style_tiro_defensa = _crear_estilo_circular(Color(0.90, 0.40, 0.10, 0.92), Color(1.0, 0.74, 0.48, 0.85), 48)
	_style_sprint_defensa = _crear_estilo_circular(Color(0.10, 0.66, 0.60, 0.92), Color(0.55, 0.95, 0.88, 0.85), 36)


func _crear_estilo_circular(bg: Color, borde: Color, radio: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = borde
	sb.corner_radius_top_left = radio
	sb.corner_radius_top_right = radio
	sb.corner_radius_bottom_right = radio
	sb.corner_radius_bottom_left = radio
	return sb


func _asignar_estilo_boton(boton: Button, estilo: StyleBoxFlat) -> void:
	if boton == null or estilo == null:
		return
	boton.add_theme_stylebox_override("normal", estilo)
	boton.add_theme_stylebox_override("hover", estilo)
	boton.add_theme_stylebox_override("pressed", estilo)


# ==============================================================================
# 2. DETECCIÓN DE GESTOS SWIPE / FLICK Y JOYSTICK MULTITÁCTIL
# ==============================================================================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	# A. Eventos Táctiles Nativos (Android / Pantallas Multitouch)
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			# 1. ¿Tocó el Joystick Virtual?
			if joystick_base:
				var pos_local_joy: Vector2 = joystick_base.get_global_transform().affine_inverse() * touch.position
				if pos_local_joy.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.5:
					_tocando_joystick = true
					_joystick_touch_id = touch.index
					_actualizar_pomo(pos_local_joy)
					return
			
			# 2. ¿Tocó Botón 3 (TIRO / ENTRADA)?
			if _punto_en_boton(btn_tiro, touch.position):
				_iniciar_toque_tiro(touch.index, touch.position)
				return
			
			# 3. ¿Tocó Botón 1 (PASE / CAMBIAR)?
			if _punto_en_boton(btn_pase, touch.position):
				_iniciar_toque_pase(touch.index, touch.position)
				return
			
			# 4. ¿Tocó Botón 2 (HUECO / PRESIÓN 2° DEF)?
			if _punto_en_boton(btn_hueco, touch.position):
				_hueco_touch_id = touch.index
				_on_hueco_down()
				return
			
			# 5. ¿Tocó Botón 4 (ESPRINTAR / ESPRINTAR + PRESIÓN)?
			if _punto_en_boton(btn_sprint, touch.position):
				_sprint_touch_id = touch.index
				_on_sprint_down()
				return
		else:
			# Liberación de dedo según su índice multitáctil
			if touch.index == _joystick_touch_id:
				_soltar_joystick()
			elif touch.index == _tiro_touch_id:
				_finalizar_toque_tiro()
			elif touch.index == _pase_touch_id:
				_finalizar_toque_pase()
			elif touch.index == _hueco_touch_id:
				_hueco_touch_id = -1
				_on_hueco_up()
			elif touch.index == _sprint_touch_id:
				_sprint_touch_id = -1
				_on_sprint_up()
	
	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _tocando_joystick and drag.index == _joystick_touch_id:
			var pos_local_joy: Vector2 = joystick_base.get_global_transform().affine_inverse() * drag.position
			_actualizar_pomo(pos_local_joy)
		elif drag.index == _tiro_touch_id:
			_actualizar_swipe_tiro(drag.position)
		elif drag.index == _pase_touch_id:
			_actualizar_swipe_pase(drag.position)
	
	# B. Soporte Mouse para pruebas en Editor / PC
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if joystick_base:
					var pos_local_joy: Vector2 = joystick_base.get_global_transform().affine_inverse() * mb.position
					if pos_local_joy.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.5:
						_tocando_joystick = true
						_actualizar_pomo(pos_local_joy)
						return
				if _tiro_touch_id == -1 and _punto_en_boton(btn_tiro, mb.position):
					_tiro_mouse_activo = true
					_iniciar_toque_tiro(-10, mb.position)
				elif _pase_touch_id == -1 and _punto_en_boton(btn_pase, mb.position):
					_pase_mouse_activo = true
					_iniciar_toque_pase(-11, mb.position)
			else:
				if _tocando_joystick and _joystick_touch_id == -1:
					_soltar_joystick()
				if _tiro_mouse_activo:
					_tiro_mouse_activo = false
					_finalizar_toque_tiro()
				if _pase_mouse_activo:
					_pase_mouse_activo = false
					_finalizar_toque_pase()
	
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _tocando_joystick and _joystick_touch_id == -1:
			var pos_local_joy: Vector2 = joystick_base.get_global_transform().affine_inverse() * mm.position
			_actualizar_pomo(pos_local_joy)
		elif _tiro_mouse_activo:
			_actualizar_swipe_tiro(mm.position)
		elif _pase_mouse_activo:
			_actualizar_swipe_pase(mm.position)


func _punto_en_boton(boton: Button, pos_global: Vector2) -> bool:
	if boton == null or not boton.visible:
		return false
	return boton.get_global_rect().grow(6.0).has_point(pos_global)


## Inicia toque en Botón TIRO (Ataque: carga potencia y escucha Swipe Up/Down | Defensa: Entrada inmediata)
func _iniciar_toque_tiro(touch_idx: int, pos_inicial: Vector2) -> void:
	_tiro_touch_id = touch_idx
	_tiro_pos_inicial = pos_inicial
	_gesto_tiro_detectado = Jugador3D.TipoTiro.NORMAL
	_resaltar_indicadores_swipe_tiro(Jugador3D.TipoTiro.NORMAL)
	
	if _modo_defensivo_actual:
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_principal_presionada(1.0, Jugador3D.TipoTiro.NORMAL)
		return
	
	_accion_cargando = "TIRO"
	_potencia_acumulada = 0.18


## Evalúa el desplazamiento vertical del dedo en el botón TIRO:
## - Swipe Down (dy >= umbral) -> Tiro Colocado / Calidad (Efecto Magnus con curva al segundo palo)
## - Swipe Up   (dy <= -umbral) -> Vaselina / Picadita (Parábola suave sobre el arquero)
func _actualizar_swipe_tiro(pos_actual: Vector2) -> void:
	if _modo_defensivo_actual or _accion_cargando != "TIRO":
		return
	
	var delta_y: float = pos_actual.y - _tiro_pos_inicial.y
	if delta_y <= -umbral_swipe_px:
		_gesto_tiro_detectado = Jugador3D.TipoTiro.VASELINA
	elif delta_y >= umbral_swipe_px:
		_gesto_tiro_detectado = Jugador3D.TipoTiro.COLOCADO
	else:
		_gesto_tiro_detectado = Jugador3D.TipoTiro.NORMAL
	
	_resaltar_indicadores_swipe_tiro(_gesto_tiro_detectado)


func _finalizar_toque_tiro() -> void:
	_tiro_touch_id = -1
	_resaltar_indicadores_swipe_tiro(Jugador3D.TipoTiro.NORMAL)
	if label_gesto_activo:
		label_gesto_activo.visible = false
	
	if _accion_cargando == "TIRO":
		var pot: float = _potencia_acumulada
		var tipo_tiro_final: int = _gesto_tiro_detectado
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		_gesto_tiro_detectado = Jugador3D.TipoTiro.NORMAL
		
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_principal_presionada(pot, tipo_tiro_final)


## Inicia toque en Botón PASE (Ataque: carga potencia y escucha Swipe Up | Defensa: Cambiar Jugador inmediato)
func _iniciar_toque_pase(touch_idx: int, pos_inicial: Vector2) -> void:
	_pase_touch_id = touch_idx
	_pase_pos_inicial = pos_inicial
	_gesto_pase_detectado = Jugador3D.TipoPase.RASO
	_resaltar_indicadores_swipe_pase(Jugador3D.TipoPase.RASO)
	
	if _modo_defensivo_actual:
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_pase_presionada(1.0, Jugador3D.TipoPase.RASO)
		return
	
	_accion_cargando = "PASE"
	_potencia_acumulada = 0.18


## Evalúa el desplazamiento vertical del dedo en el botón PASE:
## - Swipe Up (dy <= -umbral) -> Pase Elevado / Sombrerito (para superar piernas estiradas)
func _actualizar_swipe_pase(pos_actual: Vector2) -> void:
	if _modo_defensivo_actual or _accion_cargando != "PASE":
		return
	
	var delta_y: float = pos_actual.y - _pase_pos_inicial.y
	if delta_y <= -umbral_swipe_px:
		_gesto_pase_detectado = Jugador3D.TipoPase.ELEVADO
	else:
		_gesto_pase_detectado = Jugador3D.TipoPase.RASO
	
	_resaltar_indicadores_swipe_pase(_gesto_pase_detectado)


func _finalizar_toque_pase() -> void:
	_pase_touch_id = -1
	_resaltar_indicadores_swipe_pase(Jugador3D.TipoPase.RASO)
	if label_gesto_activo:
		label_gesto_activo.visible = false
	
	if _accion_cargando == "PASE":
		var pot: float = _potencia_acumulada
		var tipo_pase_final: int = _gesto_pase_detectado
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		_gesto_pase_detectado = Jugador3D.TipoPase.RASO
		
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_pase_presionada(pot, tipo_pase_final)


func _resaltar_indicadores_swipe_tiro(tipo_tiro: int) -> void:
	if label_flecha_tiro_up:
		label_flecha_tiro_up.modulate = Color(1.0, 0.95, 0.25, 1.0) if tipo_tiro == Jugador3D.TipoTiro.VASELINA else Color(1.0, 1.0, 1.0, 0.65)
	if label_flecha_tiro_down:
		label_flecha_tiro_down.modulate = Color(0.45, 0.95, 1.0, 1.0) if tipo_tiro == Jugador3D.TipoTiro.COLOCADO else Color(1.0, 1.0, 1.0, 0.65)
	
	if label_gesto_activo:
		if tipo_tiro == Jugador3D.TipoTiro.VASELINA:
			label_gesto_activo.text = "▲ VASELINA / PICADITA"
			label_gesto_activo.visible = true
		elif tipo_tiro == Jugador3D.TipoTiro.COLOCADO:
			label_gesto_activo.text = "▼ TIRO COLOCADO (CURVA)"
			label_gesto_activo.visible = true
		else:
			label_gesto_activo.visible = false


func _resaltar_indicadores_swipe_pase(tipo_pase: int) -> void:
	if label_flecha_pase_up:
		label_flecha_pase_up.modulate = Color(1.0, 0.95, 0.25, 1.0) if tipo_pase == Jugador3D.TipoPase.ELEVADO else Color(1.0, 1.0, 1.0, 0.65)
	
	if label_gesto_activo:
		if tipo_pase == Jugador3D.TipoPase.ELEVADO:
			label_gesto_activo.text = "▲ PASE ELEVADO / SOMBRERITO"
			label_gesto_activo.visible = true
		else:
			label_gesto_activo.visible = false


# ==============================================================================
# 3. BOTONES HUECO, SPRINT Y CARGA DE POTENCIA / TECLADO
# ==============================================================================

func _conectar_botones_respaldo() -> void:
	if btn_hueco:
		btn_hueco.button_down.connect(_on_hueco_down)
		btn_hueco.button_up.connect(_on_hueco_up)
	if btn_sprint:
		btn_sprint.button_down.connect(_on_sprint_down)
		btn_sprint.button_up.connect(_on_sprint_up)


func _on_hueco_down() -> void:
	if _modo_defensivo_actual:
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_hueco_presionada(1.0)
		return
	
	_accion_cargando = "HUECO"
	_potencia_acumulada = 0.18


func _on_hueco_up() -> void:
	if _accion_cargando == "HUECO":
		var pot: float = _potencia_acumulada
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		var jugador: Jugador3D = obtener_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_hueco_presionada(pot)


func _on_sprint_down() -> void:
	var jugador: Jugador3D = obtener_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_sprint_y_presion(true, _modo_defensivo_actual)


func _on_sprint_up() -> void:
	var jugador: Jugador3D = obtener_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_sprint_y_presion(false, false)


func _procesar_carga_potencia(delta: float) -> void:
	if _accion_cargando != "":
		_potencia_acumulada = clampf(_potencia_acumulada + delta * velocidad_carga_potencia, 0.0, 1.0)
		if barra_potencia:
			barra_potencia.visible = true
			barra_potencia.value = _potencia_acumulada
	else:
		if barra_potencia and barra_potencia.visible:
			barra_potencia.visible = false
			barra_potencia.value = 0.0


func _procesar_input_teclado() -> void:
	var espacio_presionado: bool = Input.is_key_pressed(KEY_SPACE)
	var x_presionado: bool = Input.is_key_pressed(KEY_X)
	var c_presionado: bool = Input.is_key_pressed(KEY_C)
	
	if espacio_presionado and not _tecla_espacio_mantenida:
		_tecla_espacio_mantenida = true
		_iniciar_toque_tiro(-20, Vector2.ZERO)
	elif not espacio_presionado and _tecla_espacio_mantenida:
		_tecla_espacio_mantenida = false
		_finalizar_toque_tiro()
	
	if x_presionado and not _tecla_x_mantenida:
		_tecla_x_mantenida = true
		_iniciar_toque_pase(-21, Vector2.ZERO)
	elif not x_presionado and _tecla_x_mantenida:
		_tecla_x_mantenida = false
		_finalizar_toque_pase()
	
	if c_presionado and not _tecla_c_mantenida:
		_tecla_c_mantenida = true
		_on_hueco_down()
	elif not c_presionado and _tecla_c_mantenida:
		_tecla_c_mantenida = false
		_on_hueco_up()


# ==============================================================================
# 4. JOYSTICK VIRTUAL Y REFERENCIA AL JUGADOR ACTIVO
# ==============================================================================

func _actualizar_pomo(pos_local: Vector2) -> void:
	_centro_joystick = joystick_base.size * 0.5
	var vector_desplazamiento: Vector2 = pos_local - _centro_joystick
	var distancia: float = vector_desplazamiento.length()
	
	if distancia > _radio_maximo_joystick:
		vector_desplazamiento = vector_desplazamiento.normalized() * _radio_maximo_joystick
	
	joystick_pomo.position = _centro_joystick + vector_desplazamiento - (joystick_pomo.size * 0.5)
	
	var direccion_normalizada: Vector2 = vector_desplazamiento / _radio_maximo_joystick
	_direccion_joystick_actual = direccion_normalizada
	var jugador: Jugador3D = obtener_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_direccion_virtual(direccion_normalizada)


func _soltar_joystick() -> void:
	_tocando_joystick = false
	_joystick_touch_id = -1
	_direccion_joystick_actual = Vector2.ZERO
	_resetear_joystick()
	var jugador: Jugador3D = obtener_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_direccion_virtual(Vector2.ZERO)


func _resetear_joystick() -> void:
	if joystick_base == null or joystick_pomo == null:
		return
	_centro_joystick = joystick_base.size * 0.5
	joystick_pomo.position = _centro_joystick - (joystick_pomo.size * 0.5)


func obtener_jugador_activo() -> Jugador3D:
	if _jugador_referencia != null and is_instance_valid(_jugador_referencia) and _jugador_referencia.es_controlado:
		return _jugador_referencia
	
	var activos: Array[Node] = get_tree().get_nodes_in_group("jugador_activo")
	if not activos.is_empty():
		_jugador_referencia = activos[0] as Jugador3D
		return _jugador_referencia
	
	if has_node(ruta_jugador):
		var j_ruta: Jugador3D = get_node(ruta_jugador) as Jugador3D
		if j_ruta and j_ruta.es_controlado:
			_jugador_referencia = j_ruta
			return _jugador_referencia
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	for jug_nodo: Node in locales:
		var j: Jugador3D = jug_nodo as Jugador3D
		if j and j.posicion_tactica != "PORTERO":
			_jugador_referencia = j
			return _jugador_referencia
	
	return null
