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
	SAQUE_MANO = 3,
	TIRO_LIBRE = 4
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

# Referencias a Tiro Libre Swipe
@onready var contenedor_tiro_libre: Control = get_node_or_null("ContenedorTiroLibre")
@onready var btn_pase_corto: Button = get_node_or_null("ContenedorTiroLibre/BotonPaseCorto") as Button

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

# Estado de Tiro Libre: Pantalla Dividida (Izquierda < 45% Paneo Cámara | Derecha >= 45% Swipe Disparo)
var _modo_tiro_libre_activo: bool = false
var _pan_touch_id: int = -1
var _pan_pos_previa: Vector2 = Vector2.ZERO
var _pan_pos_inicio: Vector2 = Vector2.ZERO
var _pan_tiempo_inicio: float = 0.0
var _capturando_swipe_tiro_libre: bool = false
var _swipe_touch_id: int = -1
var _swipe_puntos: PackedVector2Array = PackedVector2Array()
var _swipe_tiempo_inicio: float = 0.0
var _potencia_swipe_actual: float = 0.0
var _comba_swipe_actual: float = 0.0
var _en_secuencia_carrera_tl: bool = false
var _tiempo_carrera_tl: float = 0.0
var _duracion_carrera_tl: float = 0.35
var _pos_inicio_carrera_tl: Vector3 = Vector3.ZERO
var _pos_impacto_carrera_tl: Vector3 = Vector3.ZERO
var _dir_tiro_pendiente_tl: Vector3 = Vector3(1.0, 0.0, 0.0)
var _impulso_pendiente_tl: Vector3 = Vector3.ZERO
var _comba_pendiente_tl: float = 0.0
var _es_cucharita_pendiente_tl: bool = false
var _color_halo_swipe: Color = Color(0.18, 0.68, 1.0, 0.38)
var _color_linea_swipe: Color = Color(0.95, 0.98, 1.0, 0.95)
var _color_punta_swipe: Color = Color(1.0, 0.88, 0.25, 1.0)

# Estado multitáctil del Joystick
var _tocando_joystick: bool = false
var _joystick_touch_id: int = -1
var _radio_maximo_joystick: float = 78.0
var _centro_joystick: Vector2 = Vector2.ZERO
var _direccion_joystick_actual: Vector2 = Vector2.ZERO
@export var margen_tactil_boton_px: float = 18.0

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
	
	if btn_pase_corto and not btn_pase_corto.pressed.is_connected(_on_btn_pase_corto_pressed):
		btn_pase_corto.pressed.connect(_on_btn_pase_corto_pressed)
	
	if joystick_base:
		_centro_joystick = joystick_base.size * 0.5
		_resetear_joystick()
	if barra_potencia:
		barra_potencia.visible = false
	if label_gesto_activo:
		label_gesto_activo.visible = false
	if contenedor_tiro_libre:
		contenedor_tiro_libre.visible = false
	
	_aplicar_modo_hud(ModoHUD.ATAQUE)


func _draw() -> void:
	if not _modo_tiro_libre_activo:
		return

	var view_size: Vector2 = get_viewport_rect().size
	var x_divisoria: float = view_size.x * 0.45

	# 1. Línea divisoria sutil de Pantalla Dividida (Izquierda < 45% Paneo | Derecha >= 45% Disparo Swipe)
	var y_top_div: float = 80.0
	var y_bot_div: float = view_size.y - 135.0
	var paso_guion: float = 18.0
	var y_cursor: float = y_top_div
	while y_cursor < y_bot_div:
		draw_line(
			Vector2(x_divisoria, y_cursor),
			Vector2(x_divisoria, minf(y_cursor + 8.0, y_bot_div)),
			Color(0.45, 0.78, 1.0, 0.24),
			1.5,
			true
		)
		y_cursor += paso_guion

	if _swipe_puntos.size() < 2:
		return

	# 2. Halo translúcido siguiendo la curva del dedo
	draw_polyline(_swipe_puntos, _color_halo_swipe, 10.0, true)

	# 3. Guía visual de puntos (línea punteada en tiempo real) a lo largo del trazo
	var dist_acum: float = 0.0
	var separacion_puntos: float = 14.0
	draw_circle(_swipe_puntos[0], 4.5, _color_linea_swipe)
	for i: int in range(1, _swipe_puntos.size()):
		var a: Vector2 = _swipe_puntos[i - 1]
		var b: Vector2 = _swipe_puntos[i]
		var seg_len: float = a.distance_to(b)
		if seg_len < 0.001:
			continue
		var dir_seg: Vector2 = (b - a) / seg_len
		var d: float = separacion_puntos - dist_acum
		while d <= seg_len:
			var pt_dot: Vector2 = a + dir_seg * d
			draw_circle(pt_dot, 3.4, _color_linea_swipe)
			d += separacion_puntos
		dist_acum = fmod(dist_acum + seg_len, separacion_puntos)

	# 4. Flecha de dirección y curvatura en el extremo del trazo
	var pt_punta: Vector2 = _swipe_puntos[-1]
	var idx_prev: int = maxi(0, _swipe_puntos.size() - 4)
	var dir_punta: Vector2 = (pt_punta - _swipe_puntos[idx_prev]).normalized()
	if dir_punta.length_squared() < 0.01:
		dir_punta = (_swipe_puntos[-1] - _swipe_puntos[0]).normalized()
	if dir_punta.length_squared() > 0.01:
		var perp_punta: Vector2 = Vector2(-dir_punta.y, dir_punta.x)
		var ala_izq: Vector2 = pt_punta - dir_punta * 18.0 + perp_punta * 10.5
		var ala_der: Vector2 = pt_punta - dir_punta * 18.0 - perp_punta * 10.5
		var pts_flecha: PackedVector2Array = PackedVector2Array([pt_punta + dir_punta * 4.0, ala_izq, ala_der])
		draw_colored_polygon(pts_flecha, _color_punta_swipe)

	# 5. Indicador de arco de curvatura (Efecto Magnus) en el punto medio del trazo
	if absf(_comba_swipe_actual) > 0.06 and _swipe_puntos.size() >= 3:
		var p_ini: Vector2 = _swipe_puntos[0]
		var p_fin: Vector2 = _swipe_puntos[-1]
		var cuerda: Vector2 = p_fin - p_ini
		if cuerda.length() > 25.0:
			var mid_cuerda: Vector2 = (p_ini + p_fin) * 0.5
			var normal_cuerda: Vector2 = Vector2(-cuerda.y, cuerda.x).normalized()
			var p_pico_curva: Vector2 = _swipe_puntos[_swipe_puntos.size() / 2]
			var color_curva: Color = Color(0.28, 0.92, 1.0, 0.85)
			draw_line(mid_cuerda, p_pico_curva, color_curva, 2.2, true)
			var dir_flecha_curva: Vector2 = normal_cuerda * signf(_comba_swipe_actual)
			var perp_c: Vector2 = Vector2(-dir_flecha_curva.y, dir_flecha_curva.x)
			var c_tip: Vector2 = p_pico_curva + dir_flecha_curva * 8.0
			var c_a1: Vector2 = c_tip - dir_flecha_curva * 9.0 + perp_c * 5.5
			var c_a2: Vector2 = c_tip - dir_flecha_curva * 9.0 - perp_c * 5.5
			draw_colored_polygon(PackedVector2Array([c_tip, c_a1, c_a2]), color_curva)

	# 6. Barra lateral flotante de potencia junto al origen del trazo
	var origen_barra: Vector2 = _swipe_puntos[0] + Vector2(26.0, -36.0)
	var ancho_b: float = 10.0
	var alto_b: float = 72.0
	var rect_bg: Rect2 = Rect2(origen_barra.x, origen_barra.y, ancho_b, alto_b)
	draw_rect(rect_bg, Color(0.05, 0.08, 0.14, 0.82), true)
	var fill_h: float = alto_b * clampf(_potencia_swipe_actual, 0.0, 1.0)
	var col_pot: Color = Color(0.2, 0.92, 0.45, 0.95).lerp(Color(1.0, 0.28, 0.2, 0.98), clampf(_potencia_swipe_actual, 0.0, 1.0))
	draw_rect(Rect2(origen_barra.x, origen_barra.y + (alto_b - fill_h), ancho_b, fill_h), col_pot, true)
	draw_rect(rect_bg, Color(0.75, 0.9, 1.0, 0.8), false, 1.5)


func _process(delta: float) -> void:
	_procesar_carga_potencia(delta)
	_procesar_input_teclado()


func _physics_process(delta: float) -> void:
	if _en_secuencia_carrera_tl:
		_procesar_secuencia_carrera_tiro_libre(delta)
		return
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
	if _gestor_partido != null and _gestor_partido.es_tiro_libre_activo():
		if _gestor_partido.obtener_equipo_sacador() == 0:
			_aplicar_modo_hud(ModoHUD.TIRO_LIBRE)
			return
	
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
	
	if _gestor_partido != null and _gestor_partido.es_tiro_libre_activo():
		if _gestor_partido.obtener_equipo_sacador() == 0:
			_aplicar_modo_hud(ModoHUD.TIRO_LIBRE)
			return
	
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
		
		ModoHUD.TIRO_LIBRE:
			_modo_tiro_libre_activo = true
			if joystick_base: joystick_base.visible = false
			if btn_pase: btn_pase.visible = false
			if btn_hueco: btn_hueco.visible = false
			if btn_tiro: btn_tiro.visible = false
			if btn_sprint: btn_sprint.visible = false
			if barra_potencia: barra_potencia.visible = false
			if label_gesto_activo: label_gesto_activo.visible = false
			if label_flecha_tiro_up: label_flecha_tiro_up.visible = false
			if label_flecha_tiro_down: label_flecha_tiro_down.visible = false
			if label_flecha_pase_up: label_flecha_pase_up.visible = false
			if contenedor_tiro_libre: contenedor_tiro_libre.visible = true
	
	if nuevo_modo != ModoHUD.TIRO_LIBRE:
		_modo_tiro_libre_activo = false
		_capturando_swipe_tiro_libre = false
		_swipe_puntos.clear()
		queue_redraw()
		if contenedor_tiro_libre: contenedor_tiro_libre.visible = false
		if joystick_base: joystick_base.visible = true
		if btn_pase: btn_pase.visible = true
		if btn_hueco: btn_hueco.visible = true
		if btn_tiro: btn_tiro.visible = true
		if btn_sprint: btn_sprint.visible = true


## Conmuta de forma adaptativa la UI en tiros libres (Vista táctica con joystick/botones vs Vista tiro OTS con swipe)
func conmutar_vista_tiro_libre(es_tactica: bool) -> void:
	if not _modo_tiro_libre_activo:
		return
	if es_tactica:
		_capturando_swipe_tiro_libre = false
		_swipe_puntos.clear()
		queue_redraw()
		if joystick_base: joystick_base.visible = true
		if btn_pase: btn_pase.visible = true
		if btn_hueco: btn_hueco.visible = true
		if btn_tiro: btn_tiro.visible = true
	else:
		if joystick_base: joystick_base.visible = false
		if btn_pase: btn_pase.visible = false
		if btn_hueco: btn_hueco.visible = false
		if btn_tiro: btn_tiro.visible = false


func _inicializar_estilos_botones() -> void:
	# Estilos de Ataque (Posesión) con escala móvil ampliada (+30%: radios 56, 50, 62, 48)
	_style_pase_ataque = _crear_estilo_circular(Color(0.15, 0.60, 0.92, 0.92), Color(0.60, 0.85, 1.0, 0.88), 56)
	_style_hueco_ataque = _crear_estilo_circular(Color(0.12, 0.76, 0.42, 0.92), Color(0.60, 1.0, 0.75, 0.88), 50)
	_style_tiro_ataque = _crear_estilo_circular(Color(0.92, 0.22, 0.22, 0.92), Color(1.0, 0.62, 0.62, 0.88), 62)
	_style_sprint_ataque = _crear_estilo_circular(Color(0.95, 0.72, 0.12, 0.92), Color(1.0, 0.90, 0.60, 0.88), 48)
	
	# Estilos de Defensa (Sin Balón - Colores diferenciados tácticos)
	_style_pase_defensa = _crear_estilo_circular(Color(0.20, 0.42, 0.82, 0.92), Color(0.62, 0.80, 1.0, 0.88), 56)
	_style_hueco_defensa = _crear_estilo_circular(Color(0.56, 0.24, 0.78, 0.92), Color(0.84, 0.65, 1.0, 0.88), 50)
	_style_tiro_defensa = _crear_estilo_circular(Color(0.90, 0.40, 0.10, 0.92), Color(1.0, 0.74, 0.48, 0.88), 62)
	_style_sprint_defensa = _crear_estilo_circular(Color(0.10, 0.66, 0.60, 0.92), Color(0.55, 0.95, 0.88, 0.88), 48)


func _crear_estilo_circular(bg: Color, borde: Color, radio: int) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
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
	
	# Si está activo el modo Tiro Libre, capturar exclusivamente el trazo táctil (Swipe) y botón Pase Corto
	if _modo_tiro_libre_activo:
		_manejar_input_swipe_tiro_libre(event)
		return
	
	# A. Eventos Táctiles Nativos (Android / Pantallas Multitouch)
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			# 1. ¿Tocó el Joystick Virtual?
			if joystick_base:
				var pos_local_joy: Vector2 = joystick_base.get_global_transform().affine_inverse() * touch.position
				if pos_local_joy.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.55:
					_tocando_joystick = true
					_joystick_touch_id = touch.index
					_actualizar_pomo(pos_local_joy)
					return
			
			# 2. Selección ergonómica del botón de acción más cercano dentro del área táctil ampliada
			var boton_tocado: Button = _detectar_boton_tocado(touch.position)
			if boton_tocado == btn_tiro:
				_iniciar_toque_tiro(touch.index, touch.position)
				return
			elif boton_tocado == btn_pase:
				_iniciar_toque_pase(touch.index, touch.position)
				return
			elif boton_tocado == btn_hueco:
				_hueco_touch_id = touch.index
				_on_hueco_down()
				return
			elif boton_tocado == btn_sprint:
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
					if pos_local_joy.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.55:
						_tocando_joystick = true
						_actualizar_pomo(pos_local_joy)
						return
				var boton_mouse: Button = _detectar_boton_tocado(mb.position)
				if _tiro_touch_id == -1 and boton_mouse == btn_tiro:
					_tiro_mouse_activo = true
					_iniciar_toque_tiro(-10, mb.position)
				elif _pase_touch_id == -1 and boton_mouse == btn_pase:
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


## Detecta qué botón fue presionado usando un área circular ampliada (+margen_tactil_boton_px)
## y priorizando el centro más cercano para evitar toques erróneos en pantallas táctiles densas.
func _detectar_boton_tocado(pos_global: Vector2) -> Button:
	var botones: Array[Button] = [btn_tiro, btn_pase, btn_hueco, btn_sprint]
	var mejor_boton: Button = null
	var menor_dist_norm: float = 999.0
	
	for b: Button in botones:
		if b == null or not b.visible:
			continue
		var rect: Rect2 = b.get_global_rect()
		var centro: Vector2 = rect.get_center()
		var radio_efectivo: float = (maxf(rect.size.x, rect.size.y) * 0.5) + margen_tactil_boton_px
		var dist: float = pos_global.distance_to(centro)
		if dist <= radio_efectivo:
			var dist_norm: float = dist / maxf(1.0, radio_efectivo)
			if dist_norm < menor_dist_norm:
				menor_dist_norm = dist_norm
				mejor_boton = b
	
	return mejor_boton


func _punto_en_boton(boton: Button, pos_global: Vector2) -> bool:
	return _detectar_boton_tocado(pos_global) == boton


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
	if _modo_tiro_libre_activo:
		return
	
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


# ==============================================================================
# 5. PANTALLA DIVIDIDA EN TIRO LIBRE (PANEO IZQ 45% + SWIPE DER 55%) Y CARRERA PREVIA
# ==============================================================================

func _manejar_input_swipe_tiro_libre(event: InputEvent) -> void:
	if _en_secuencia_carrera_tl:
		return

	var view_w: float = get_viewport_rect().size.x
	var limite_x_paneo: float = view_w * 0.45

	# A. Eventos ScreenTouch (Android / Pantallas Táctiles)
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _es_posicion_en_boton_pase_corto(touch.position):
				_on_btn_pase_corto_pressed()
				return
			if touch.position.x < limite_x_paneo:
				_iniciar_paneo_camara_tl(touch.index, touch.position)
			else:
				_iniciar_swipe_tiro_libre(touch.index, touch.position)
		else:
			if touch.index == _pan_touch_id:
				_finalizar_paneo_camara_tl(touch.position)
			elif touch.index == _swipe_touch_id:
				_finalizar_swipe_tiro_libre()

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _pan_touch_id:
			_actualizar_paneo_camara_tl(drag.position)
		elif drag.index == _swipe_touch_id:
			_actualizar_swipe_tiro_libre(drag.position)

	# B. Eventos de Mouse (Pruebas en Editor / PC)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _es_posicion_en_boton_pase_corto(mb.position):
					_on_btn_pase_corto_pressed()
					return
				if mb.position.x < limite_x_paneo:
					_iniciar_paneo_camara_tl(-98, mb.position)
				else:
					_iniciar_swipe_tiro_libre(-99, mb.position)
			else:
				if _pan_touch_id == -98:
					_finalizar_paneo_camara_tl(mb.position)
				if _swipe_touch_id == -99:
					_finalizar_swipe_tiro_libre()

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _pan_touch_id == -98:
			_actualizar_paneo_camara_tl(mm.position)
		elif _swipe_touch_id == -99 and _capturando_swipe_tiro_libre:
			_actualizar_swipe_tiro_libre(mm.position)


func _es_posicion_en_boton_pase_corto(pos_pantalla: Vector2) -> bool:
	if btn_pase_corto and btn_pase_corto.is_visible_in_tree():
		return btn_pase_corto.get_global_rect().has_point(pos_pantalla)
	return false


func _obtener_camara_transmision() -> CamaraTransmision:
	if get_viewport() and get_viewport().get_camera_3d() is CamaraTransmision:
		return get_viewport().get_camera_3d() as CamaraTransmision
	return null


func _iniciar_paneo_camara_tl(touch_id: int, pos: Vector2) -> void:
	_pan_touch_id = touch_id
	_pan_pos_previa = pos
	_pan_pos_inicio = pos
	_pan_tiempo_inicio = Time.get_ticks_msec() / 1000.0


func _actualizar_paneo_camara_tl(pos: Vector2) -> void:
	var delta_x: float = pos.x - _pan_pos_previa.x
	_pan_pos_previa = pos
	var camara: CamaraTransmision = _obtener_camara_transmision()
	if camara != null:
		camara.ajustar_paneo_tiro_libre(-delta_x * 0.0022)
		var dir_apuntado: Vector3 = camara.obtener_direccion_apuntado_tl()
		var sacador: Jugador3D = _gestor_partido.obtener_sacador_actual() if _gestor_partido else obtener_jugador_activo()
		var balon: Balon3D = _gestor_partido.obtener_balon() if _gestor_partido else null
		if sacador != null and is_instance_valid(sacador) and balon != null and is_instance_valid(balon):
			var vec_der: Vector3 = Vector3(-dir_apuntado.z, 0.0, dir_apuntado.x).normalized()
			var pos_lanzador: Vector3 = balon.global_position - dir_apuntado * 1.45 - vec_der * 0.48
			pos_lanzador.y = 0.0
			sacador.fijar_en_saque(true, pos_lanzador)
			sacador.rotation.y = atan2(-dir_apuntado.x, -dir_apuntado.z)


func _finalizar_paneo_camara_tl(pos: Vector2 = Vector2.ZERO) -> void:
	if _pan_touch_id != -1 and pos != Vector2.ZERO:
		var duracion: float = (Time.get_ticks_msec() / 1000.0) - _pan_tiempo_inicio
		var dist_recorrida: float = pos.distance_to(_pan_pos_inicio)
		if dist_recorrida < 25.0 and duracion < 0.40:
			_intentar_pase_tactil_tl(pos)
	_pan_touch_id = -1


func _iniciar_swipe_tiro_libre(touch_id: int, pos: Vector2) -> void:
	_swipe_touch_id = touch_id
	_capturando_swipe_tiro_libre = true
	_swipe_puntos.clear()
	_swipe_puntos.append(pos)
	_swipe_tiempo_inicio = Time.get_ticks_msec() / 1000.0
	_potencia_swipe_actual = 0.15
	_comba_swipe_actual = 0.0
	if barra_potencia:
		barra_potencia.visible = true
		barra_potencia.value = _potencia_swipe_actual
	queue_redraw()


func _actualizar_swipe_tiro_libre(pos: Vector2) -> void:
	if not _capturando_swipe_tiro_libre:
		return
	if _swipe_puntos.is_empty() or pos.distance_to(_swipe_puntos[-1]) >= 4.0:
		_swipe_puntos.append(pos)
		_recalcular_metricas_swipe_en_vivo()
		queue_redraw()


func _recalcular_metricas_swipe_en_vivo() -> void:
	if _swipe_puntos.size() < 2:
		return
	var duracion: float = maxf(0.04, (Time.get_ticks_msec() / 1000.0) - _swipe_tiempo_inicio)
	var longitud_acum: float = 0.0
	for i: int in range(1, _swipe_puntos.size()):
		longitud_acum += _swipe_puntos[i].distance_to(_swipe_puntos[i - 1])
	var vel_px_s: float = longitud_acum / duracion
	var factor_len: float = clampf(longitud_acum / 260.0, 0.15, 1.0)
	var factor_vel: float = clampf((vel_px_s - 350.0) / 1850.0, 0.15, 1.0)
	_potencia_swipe_actual = clampf(factor_len * 0.55 + factor_vel * 0.45, 0.15, 1.0)
	if barra_potencia:
		barra_potencia.visible = true
		barra_potencia.value = _potencia_swipe_actual

	var p0: Vector2 = _swipe_puntos[0]
	var p1: Vector2 = _swipe_puntos[-1]
	var delta_vec: Vector2 = p1 - p0
	var cuerda_len: float = delta_vec.length()
	if cuerda_len > 20.0:
		var norm_cuerda: Vector2 = Vector2(-delta_vec.y, delta_vec.x) / cuerda_len
		var max_dist_perp: float = 0.0
		for p: Vector2 in _swipe_puntos:
			var d_perp: float = (p - p0).dot(norm_cuerda)
			if absf(d_perp) > absf(max_dist_perp):
				max_dist_perp = d_perp
		var ratio_curva: float = max_dist_perp / cuerda_len
		# Si la panza del arco se abre a la izquierda (d_perp < 0), el trazo cierra a la derecha (curvatura > 0);
		# si la panza se abre a la derecha (d_perp > 0), el trazo cierra a la izquierda (curvatura < 0).
		_comba_swipe_actual = clampf(-ratio_curva * 3.4, -1.0, 1.0) if absf(ratio_curva) > 0.04 else 0.0


func _finalizar_swipe_tiro_libre() -> void:
	if not _capturando_swipe_tiro_libre:
		return
	_capturando_swipe_tiro_libre = false
	_swipe_touch_id = -1

	if _swipe_puntos.size() < 2:
		var p_tap_unico: Vector2 = _swipe_puntos[0] if not _swipe_puntos.is_empty() else Vector2.ZERO
		_swipe_puntos.clear()
		if barra_potencia:
			barra_potencia.visible = false
		queue_redraw()
		if p_tap_unico != Vector2.ZERO:
			_intentar_pase_tactil_tl(p_tap_unico)
		return

	var p0: Vector2 = _swipe_puntos[0]
	var p1: Vector2 = _swipe_puntos[-1]
	var delta_vec: Vector2 = p1 - p0
	var len_total: float = delta_vec.length()

	# Umbral mínimo de trazo (35px): si es menor, se procesa como Toque Corto (Tap) para pase a compañero
	if len_total < 35.0:
		_swipe_puntos.clear()
		if barra_potencia:
			barra_potencia.visible = false
		queue_redraw()
		_intentar_pase_tactil_tl(p0)
		return

	_recalcular_metricas_swipe_en_vivo()
	_procesar_calculo_disparo_swipe(p0, p1, delta_vec)


## Detecta si un toque corto (Tap) sobre la pantalla apuntó a un compañero de equipo en vista de tiro libre
func _detectar_companero_tocado_tl(pos_pantalla: Vector2) -> Jugador3D:
	var camara: CamaraTransmision = _obtener_camara_transmision()
	if camara == null or get_viewport() == null:
		return null
	var ray_origin: Vector3 = camara.project_ray_origin(pos_pantalla)
	var ray_dir: Vector3 = camara.project_ray_normal(pos_pantalla)

	var space_state: PhysicsDirectSpaceState3D = get_viewport().get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_dir * 50.0)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var col: Object = hit.get("collider")
		if col is Jugador3D and (col as Jugador3D).equipo == Jugador3D.Equipo.LOCAL:
			return col as Jugador3D

	var companeros: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var candidato: Jugador3D = null
	var menor_dist: float = 1.35
	for n: Node in companeros:
		var j: Jugador3D = n as Jugador3D
		if j == null or not is_instance_valid(j):
			continue
		var pos_torso: Vector3 = j.global_position + Vector3(0.0, 0.9, 0.0)
		var proy: float = (pos_torso - ray_origin).dot(ray_dir)
		if proy > 0.5:
			var pt_cercano: Vector3 = ray_origin + ray_dir * proy
			var dist: float = pt_cercano.distance_to(pos_torso)
			if dist < menor_dist:
				menor_dist = dist
				candidato = j
	return candidato


const VEL_PASE_AL_PIE_TL: float = 8.5
const VEL_PASE_AL_HUECO_TL: float = 11.5


## Ejecuta un pase al pie o pase al hueco en profundidad mediante Tap táctil en tiro libre
func _intentar_pase_tactil_tl(pos_pantalla: Vector2) -> bool:
	var nodo_entrenamiento: Node = get_tree().get_first_node_in_group("entrenamiento_tiro_libre")
	if nodo_entrenamiento == null and get_tree().current_scene and get_tree().current_scene.has_method("_procesar_toque_tactil_pase"):
		nodo_entrenamiento = get_tree().current_scene
	if nodo_entrenamiento != null and nodo_entrenamiento.has_method("_procesar_toque_tactil_pase"):
		return bool(nodo_entrenamiento.call("_procesar_toque_tactil_pase", pos_pantalla))

	var sacador: Jugador3D = _gestor_partido.obtener_sacador_actual() if _gestor_partido else obtener_jugador_activo()
	var balon: Balon3D = _gestor_partido.obtener_balon() if _gestor_partido else null
	if balon == null:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			balon = balones[0] as Balon3D
	if sacador == null or not is_instance_valid(sacador) or balon == null:
		return false

	var camara: Camera3D = _obtener_camara_transmision()
	if camara == null and get_viewport() != null:
		camara = get_viewport().get_camera_3d()
	if camara == null:
		return false

	# 1. Probar colisión directa con compañero de equipo (Pase al Pie)
	var receptor: Jugador3D = _detectar_companero_tocado_tl(pos_pantalla)
	if receptor != null and receptor != sacador:
		return _ejecutar_pase_al_pie_tl(sacador, balon, receptor)

	# 2. Probar proyección sobre el suelo libre Plane(Vector3.UP, 0.0) (Pase al Hueco en Profundidad)
	var ray_origin: Vector3 = camara.project_ray_origin(pos_pantalla)
	var ray_dir: Vector3 = camara.project_ray_normal(pos_pantalla)
	var plano_suelo: Plane = Plane(Vector3.UP, 0.0)
	var hit_suelo = plano_suelo.intersects_ray(ray_origin, ray_dir)
	if hit_suelo != null:
		var punto_suelo: Vector3 = hit_suelo
		if _es_espacio_libre_viable_tl(punto_suelo, balon.global_position):
			var comp_hueco: Jugador3D = _buscar_companero_mejor_perfilado_tl(punto_suelo, sacador)
			if comp_hueco != null:
				return _ejecutar_pase_al_hueco_tl(sacador, balon, comp_hueco, punto_suelo)

	return false


func _es_espacio_libre_viable_tl(punto: Vector3, pos_balon: Vector3) -> bool:
	if punto.x < -18.5 or punto.x > 19.5 or absf(punto.z) > 9.5:
		return false
	if punto.x < pos_balon.x - 1.0:
		return false
	var d: float = pos_balon.distance_to(punto)
	return d >= 2.0 and d <= 25.0


func _buscar_companero_mejor_perfilado_tl(punto: Vector3, sacador: Jugador3D) -> Jugador3D:
	var companeros: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var mejor: Jugador3D = null
	var menor_dist: float = 999.0
	for n: Node in companeros:
		var j: Jugador3D = n as Jugador3D
		if j == null or not is_instance_valid(j) or j == sacador or j.es_arquero or j.posicion_tactica == "PORTERO":
			continue
		var d: float = j.global_position.distance_to(punto)
		if d < menor_dist:
			menor_dist = d
			mejor = j
	return mejor


func _ejecutar_pase_al_pie_tl(sacador: Jugador3D, balon: Balon3D, receptor: Jugador3D) -> bool:
	var pos_b: Vector3 = balon.global_position
	var dir_pase: Vector3 = (receptor.global_position - pos_b).normalized()
	dir_pase.y = 0.0
	if dir_pase.length_squared() > 0.01:
		dir_pase = dir_pase.normalized()
		sacador.look_at(sacador.global_position + dir_pase * 5.0, Vector3.UP)
		sacador.rotation.x = 0.0
		sacador.rotation.z = 0.0
	sacador._t_anim_patada = 0.28
	sacador.soltar_posesion()

	receptor.orientar_y_preparar_recepcion(pos_b)

	var impulso: Vector3 = dir_pase * (VEL_PASE_AL_PIE_TL * balon.mass)
	balon.sacador_autorizado = null
	if balon.has_method("liberar_pase_raso"):
		balon.liberar_pase_raso(impulso, 0)
	else:
		balon.linear_damp = 0.3
		balon.angular_damp = 1.3
		balon.liberar(impulso, 0, true)

	_aplicar_modo_hud(ModoHUD.ATAQUE)
	return true


func _ejecutar_pase_al_hueco_tl(sacador: Jugador3D, balon: Balon3D, receptor: Jugador3D, punto_suelo: Vector3) -> bool:
	var pos_b: Vector3 = balon.global_position
	var punto_destino: Vector3 = Vector3(punto_suelo.x, 0.0, punto_suelo.z)
	var dir_pase: Vector3 = (punto_destino - pos_b).normalized()
	dir_pase.y = 0.0
	if dir_pase.length_squared() > 0.01:
		dir_pase = dir_pase.normalized()
		sacador.look_at(sacador.global_position + dir_pase * 5.0, Vector3.UP)
		sacador.rotation.x = 0.0
		sacador.rotation.z = 0.0
	sacador._t_anim_patada = 0.28
	sacador.soltar_posesion()

	receptor.correr_al_espacio(punto_destino, 2.5)

	var impulso: Vector3 = dir_pase * (VEL_PASE_AL_HUECO_TL * balon.mass)
	balon.sacador_autorizado = null
	if balon.has_method("liberar_al_hueco"):
		balon.liberar_al_hueco(impulso, punto_destino, 0, true)
	else:
		balon.linear_damp = 0.3
		balon.liberar(impulso, 0, true)

	_aplicar_modo_hud(ModoHUD.ATAQUE)
	return true


## Transforma el vector del trazo 2D al espacio del mundo 3D usando el vector frontal (`-camera.global_transform.basis.z`)
## y el vector lateral (`camera.global_transform.basis.x`) de la cámara activa, respetando la pérdida de velocidad lineal
## en tiros bombeados y aplicando la mecánica de "Cucharita" (backspin regresivo) si el trazo vertical es muy pronunciado.
func _procesar_calculo_disparo_swipe(_p0: Vector2, _p1: Vector2, delta_vec: Vector2) -> void:
	var pot_norm: float = clampf(_potencia_swipe_actual, 0.35, 1.0)
	var rapidez_base: float = lerpf(14.5, 27.5, pot_norm)

	var view_rect: Rect2 = get_viewport_rect()
	var desvio_x_norm: float = clampf(delta_vec.x / (view_rect.size.x * 0.32), -1.0, 1.0)
	var dist_vertical_px: float = maxf(25.0, -delta_vec.y)
	var altura_norm: float = clampf(dist_vertical_px / (view_rect.size.y * 0.42), 0.05, 1.0)

	# 1. Proyección de los ejes de la cámara activa al mundo 3D: frontal (-basis.z) y lateral (+basis.x)
	var camara: Camera3D = _obtener_camara_transmision()
	if camara == null and get_viewport() != null:
		camara = get_viewport().get_camera_3d()
	var vector_frontal: Vector3 = Vector3(1.0, 0.0, 0.0)
	var vector_lateral: Vector3 = Vector3(0.0, 0.0, 1.0)
	if camara != null and is_instance_valid(camara):
		var frente_cam: Vector3 = -camara.global_transform.basis.z
		frente_cam.y = 0.0
		if frente_cam.length_squared() > 0.001:
			vector_frontal = frente_cam.normalized()
		var lat_cam: Vector3 = camara.global_transform.basis.x
		lat_cam.y = 0.0
		if lat_cam.length_squared() > 0.001:
			vector_lateral = lat_cam.normalized()

	# 2. Detectar gesto de "Cucharita" (trazo vertical muy pronunciado con elevación de vaselina/pase elevado)
	var es_cucharita: bool = (altura_norm >= 0.84 and absf(desvio_x_norm) < 0.38 and pot_norm < 0.76)

	# 3. Pérdida de velocidad lineal proporcional a la altura si se ejecuta un tiro bombeado
	var factor_bombeo: float = clampf((altura_norm - 0.38) / 0.62, 0.0, 1.0)
	var rapidez_efectiva: float = rapidez_base * lerpf(1.0, 0.80, factor_bombeo)
	var comp_vertical_y: float = lerpf(0.05, 0.27, altura_norm)

	# 4. Dirección 3D combinando vector frontal, desviación lateral del trazo y apertura inicial de comba
	var dir_horiz: Vector3 = (
		vector_frontal
		+ vector_lateral * (desvio_x_norm * 0.36 - _comba_swipe_actual * 0.16)
	).normalized()
	var dir_tiro_3d: Vector3 = Vector3(dir_horiz.x, comp_vertical_y, dir_horiz.z).normalized()

	_iniciar_secuencia_carrera_tiro_libre(dir_tiro_3d, rapidez_efectiva, _comba_swipe_actual, es_cucharita)

	var tw: Tween = create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void:
		_swipe_puntos.clear()
		if barra_potencia:
			barra_potencia.visible = false
		queue_redraw()
	)


func _iniciar_secuencia_carrera_tiro_libre(
	dir_tiro: Vector3,
	rapidez_tiro: float,
	comba: float,
	es_cucharita: bool = false
) -> void:
	var balon: Balon3D = _gestor_partido.obtener_balon() if _gestor_partido else null
	if balon == null:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			balon = balones[0] as Balon3D
	if balon == null:
		return

	var sacador: Jugador3D = _gestor_partido.obtener_sacador_actual() if _gestor_partido else obtener_jugador_activo()
	var pos_b: Vector3 = balon.global_position

	_dir_tiro_pendiente_tl = dir_tiro
	_impulso_pendiente_tl = dir_tiro * (rapidez_tiro * balon.mass)
	_comba_pendiente_tl = comba
	_es_cucharita_pendiente_tl = es_cucharita
	_tiempo_carrera_tl = 0.0
	_duracion_carrera_tl = 0.35
	_en_secuencia_carrera_tl = true

	if sacador and is_instance_valid(sacador):
		_pos_inicio_carrera_tl = sacador.global_position
		var dir_plana: Vector3 = Vector3(dir_tiro.x, 0.0, dir_tiro.z).normalized()
		var vec_der: Vector3 = Vector3(-dir_plana.z, 0.0, dir_plana.x).normalized()
		_pos_impacto_carrera_tl = Vector3(pos_b.x, 0.0, pos_b.z) - dir_plana * 0.38 - vec_der * 0.16
		sacador._en_carrera_tiro_libre = true
		var dir_aprox: Vector3 = (_pos_impacto_carrera_tl - _pos_inicio_carrera_tl).normalized()
		if dir_aprox.length_squared() > 0.01:
			sacador.rotation.y = atan2(-dir_aprox.x, -dir_aprox.z)


func _procesar_secuencia_carrera_tiro_libre(delta: float) -> void:
	_tiempo_carrera_tl += delta
	var progreso: float = clampf(_tiempo_carrera_tl / _duracion_carrera_tl, 0.0, 1.0)

	var sacador: Jugador3D = _gestor_partido.obtener_sacador_actual() if _gestor_partido else obtener_jugador_activo()
	if sacador and is_instance_valid(sacador):
		var pos_interp: Vector3 = _pos_inicio_carrera_tl.lerp(_pos_impacto_carrera_tl, progreso)
		sacador._pos_anclaje_saque = pos_interp
		sacador.global_position = pos_interp
		if progreso >= 0.72 and sacador._t_anim_patada <= 0.0:
			sacador._en_carrera_tiro_libre = false
			sacador._t_anim_patada = 0.28

	if progreso >= 1.0:
		_en_secuencia_carrera_tl = false
		_aplicar_impacto_post_carrera_tl()


func _aplicar_impacto_post_carrera_tl() -> void:
	var balon: Balon3D = _gestor_partido.obtener_balon() if _gestor_partido else null
	if balon == null:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			balon = balones[0] as Balon3D
	if balon == null:
		_aplicar_modo_hud(ModoHUD.ATAQUE)
		return

	var sacador: Jugador3D = _gestor_partido.obtener_sacador_actual() if _gestor_partido else obtener_jugador_activo()
	if sacador and is_instance_valid(sacador):
		sacador._en_carrera_tiro_libre = false
		sacador._en_posicion_saque = false
		sacador._t_anim_patada = 0.28
		sacador.soltar_posesion()
		sacador.rotation.y = atan2(-_dir_tiro_pendiente_tl.x, -_dir_tiro_pendiente_tl.z)
		sacador.velocity = Vector3.ZERO

	var camara: CamaraTransmision = _obtener_camara_transmision()
	if camara != null:
		camara.notificar_impacto_tiro_libre()

	var cam_activa: Camera3D = camara if camara != null else (get_viewport().get_camera_3d() if get_viewport() else null)
	if absf(_comba_pendiente_tl) > 0.04 or _es_cucharita_pendiente_tl:
		balon.liberar_tiro_libre_swipe(_impulso_pendiente_tl, _comba_pendiente_tl, 0, cam_activa, _es_cucharita_pendiente_tl)
	else:
		balon.liberar(_impulso_pendiente_tl, 0, false)

	_aplicar_modo_hud(ModoHUD.ATAQUE)


func _on_btn_pase_corto_pressed() -> void:
	if not _modo_tiro_libre_activo or _en_secuencia_carrera_tl:
		return

	var sacador: Jugador3D = null
	if _gestor_partido:
		sacador = _gestor_partido.obtener_sacador_actual()
	if sacador == null:
		sacador = obtener_jugador_activo()

	if sacador and is_instance_valid(sacador):
		sacador.accion_pase_presionada(0.50, Jugador3D.TipoPase.RASO)

	_aplicar_modo_hud(ModoHUD.ATAQUE)

