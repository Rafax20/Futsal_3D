class_name HUDPartido
extends CanvasLayer

## Interfaz de partido móvil estilo FC Mobile / eFootball.
## Incluye joystick virtual multitáctil, botones de acción contextuales dinámicos
## con sistema de carga de potencia (mientras más se mantenga presionado, mayor fuerza en tiro y pase),
## marcador con tiempo real, banner de anuncios reglamentarios y menú modal de pausa.

@export var ruta_jugador: NodePath = ^"../Jugadores/Local_Pivot"

# Referencias a nodos del Joystick
@onready var joystick_base: Control = $MargenControles/JoystickBase
@onready var joystick_pomo: Panel = $MargenControles/JoystickBase/Pomo

# Referencias a botones de acción y barra de potencia
@onready var btn_tiro: Button = $MargenControles/BotonesAccion/BotonTiro
@onready var btn_pase: Button = $MargenControles/BotonesAccion/BotonPase
@onready var btn_hueco: Button = $MargenControles/BotonesAccion/BotonHueco
@onready var btn_sprint: Button = $MargenControles/BotonesAccion/BotonSprint
@onready var barra_potencia: ProgressBar = $MargenControles/BarraPotencia

# Referencias al marcador, escudos, ficha de jugador y anuncios
@onready var escudo_local: ColorRect = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/EscudoLocal") as ColorRect
@onready var label_local: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelLocal") as Label
@onready var label_marcador: Label = $MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelGoles
@onready var label_vis: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelVis") as Label
@onready var escudo_vis: ColorRect = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/EscudoVis") as ColorRect
@onready var label_tiempo: Label = $MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelTiempo
@onready var label_jugador_activo: Label = get_node_or_null("PanelFichaJugador/LabelJugadorActivo") as Label
@onready var btn_pausa: Button = $BotonPausa
@onready var banner_anuncio: PanelContainer = $BannerAnuncio
@onready var label_anuncio: Label = $BannerAnuncio/LabelAnuncio

# Referencias al menú de pausa
@onready var menu_pausa: Control = $MenuPausaModal
@onready var btn_continuar: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonContinuar
@onready var btn_reiniciar: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonReiniciar
@onready var btn_salir: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonSalir

# Estado del joystick táctil
var _jugador_referencia: Jugador3D = null
var _tocando_joystick: bool = false
var _joystick_touch_id: int = -1
var _radio_maximo_joystick: float = 65.0
var _centro_joystick: Vector2 = Vector2.ZERO

# Estado de posesión y anuncios
var _modo_defensivo_actual: bool = false
var _estado_botones_previo: int = -1 # 0: Ataque, 1: Defensa, 2: Saque
var _tiempo_anuncio: float = 0.0

# Sistema de Carga de Potencia (eFootball / FC Mobile)
var _accion_cargando: String = "" # "TIRO", "PASE", "HUECO"
var _potencia_acumulada: float = 0.0
var _velocidad_carga: float = 1.65 # Llena la barra progresivamente según el tiempo presionado
var _tecla_espacio_mantenida: bool = false
var _tecla_x_mantenida: bool = false
var _tecla_c_mantenida: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud_partido")
	
	if GameManager and not GameManager.partido_en_curso:
		GameManager.iniciar_partido()
	
	_configurar_info_equipos_futsal_3d()
	_conectar_jugador()
	_conectar_botones()
	_conectar_game_manager()
	
	_centro_joystick = joystick_base.size * 0.5
	_resetear_joystick()
	menu_pausa.visible = false
	if banner_anuncio:
		banner_anuncio.visible = false
	if barra_potencia:
		barra_potencia.visible = false


func _configurar_info_equipos_futsal_3d() -> void:
	var info_loc: Dictionary = Futsal_3D.obtener_info_equipo(true)
	var info_vis: Dictionary = Futsal_3D.obtener_info_equipo(false)
	if label_local and not info_loc.is_empty():
		label_local.text = str(info_loc.get("siglas", "RFC"))
	if escudo_local and not info_loc.is_empty():
		escudo_local.color = Color.from_string(str(info_loc.get("color_primario", "#D92626")), Color(0.85, 0.15, 0.15))
	if label_vis and not info_vis.is_empty():
		label_vis.text = str(info_vis.get("siglas", "ASF"))
	if escudo_vis and not info_vis.is_empty():
		escudo_vis.color = Color.from_string(str(info_vis.get("color_primario", "#F2D91A")), Color(0.95, 0.85, 0.1))


func _process(delta: float) -> void:
	_procesar_carga_potencia(delta)
	_procesar_input_teclado_carga()


func _physics_process(delta: float) -> void:
	_gestionar_temporizador_anuncio(delta)
	_actualizar_contexto_botones()
	_actualizar_ficha_jugador_activo()


func _gestionar_temporizador_anuncio(delta: float) -> void:
	if _tiempo_anuncio > 0.0:
		_tiempo_anuncio -= delta
		if _tiempo_anuncio <= 0.0 and banner_anuncio:
			banner_anuncio.visible = false


## Muestra un banner llamativo estilo transmisión (ej: "¡SAQUE DE BANDA!", "¡PARADÓN!")
func mostrar_anuncio(texto: String, duracion: float = 1.4) -> void:
	if banner_anuncio and label_anuncio:
		label_anuncio.text = texto
		banner_anuncio.visible = true
		_tiempo_anuncio = duracion


## Muestra en tiempo real el nombre, dorsal, equipo y media OVR del jugador controlado
func _actualizar_ficha_jugador_activo() -> void:
	if label_jugador_activo == null:
		return
	var jugador: Jugador3D = _actualizar_jugador_activo()
	if jugador and is_instance_valid(jugador):
		var sufijo_estado: String = "  •  [SAQUE FIJO]" if jugador._en_posicion_saque else ""
		label_jugador_activo.text = "#%d %s [%s]  •  OVR %d%s" % [
			jugador.dorsal,
			jugador.nombre_jugador if jugador.nombre_jugador != "" else jugador.posicion_tactica,
			jugador.siglas_equipo,
			jugador.get_media_ovr(),
			sufijo_estado
		]


## Actualiza los textos de los botones según la posesión (Ataque, Saque Fijo o Defensa estilo FC Mobile / eFootball)
func _actualizar_contexto_botones() -> void:
	var es_defensa: bool = false
	var es_saque_local: bool = false
	var jugador: Jugador3D = _actualizar_jugador_activo()
	
	if jugador and is_instance_valid(jugador) and jugador._en_posicion_saque:
		es_saque_local = true
		es_defensa = false
	else:
		var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
		if not balones.is_empty():
			var balon: Balon3D = balones[0] as Balon3D
			if balon and is_instance_valid(balon):
				if balon.sacador_autorizado != null:
					var sac_aut: Jugador3D = balon.sacador_autorizado as Jugador3D
					if sac_aut and sac_aut.equipo == Jugador3D.Equipo.VISITANTE:
						es_defensa = true
				elif balon.esta_siendo_conducido() and balon.portador_actual != null:
					var portador: Jugador3D = balon.portador_actual as Jugador3D
					if portador and portador.equipo == Jugador3D.Equipo.VISITANTE:
						es_defensa = true
				else:
					if jugador and jugador.global_position.distance_to(balon.global_position) > 2.6:
						es_defensa = true
	
	_modo_defensivo_actual = es_defensa
	var estado_botones: int = 2 if es_saque_local else (1 if es_defensa else 0)
	
	if estado_botones != _estado_botones_previo:
		_estado_botones_previo = estado_botones
		if estado_botones == 2:
			btn_tiro.text = "DESPEJE"
			btn_pase.text = "SACAR"
			btn_hueco.text = "AL HUECO"
			btn_sprint.text = "FIJO"
		elif estado_botones == 1:
			btn_tiro.text = "ENTRADA"
			btn_pase.text = "CAMBIAR"
			btn_hueco.text = "PRESIÓN"
			btn_sprint.text = "SPRINT"
		else:
			btn_tiro.text = "TIRO"
			btn_pase.text = "PASE"
			btn_hueco.text = "HUECO"
			btn_sprint.text = "SPRINT"



func _conectar_jugador() -> void:
	if has_node(ruta_jugador):
		_jugador_referencia = get_node(ruta_jugador) as Jugador3D
	else:
		_actualizar_jugador_activo()


func _actualizar_jugador_activo() -> Jugador3D:
	if _jugador_referencia != null and is_instance_valid(_jugador_referencia) and _jugador_referencia.es_controlado:
		return _jugador_referencia
	
	var activos: Array[Node] = get_tree().get_nodes_in_group("jugador_activo")
	if not activos.is_empty():
		_jugador_referencia = activos[0] as Jugador3D
		return _jugador_referencia
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	for jug_nodo: Node in locales:
		var j: Jugador3D = jug_nodo as Jugador3D
		if j and j.posicion_tactica != "PORTERO":
			_jugador_referencia = j
			return _jugador_referencia
		
	return null


func _conectar_botones() -> void:
	# Sistema de pulsación mantenida (Carga de potencia al presionar, ejecución al soltar)
	btn_tiro.button_down.connect(_on_tiro_down)
	btn_tiro.button_up.connect(_on_tiro_up)
	
	btn_pase.button_down.connect(_on_pase_down)
	btn_pase.button_up.connect(_on_pase_up)
	
	btn_hueco.button_down.connect(_on_hueco_down)
	btn_hueco.button_up.connect(_on_hueco_up)
	
	btn_sprint.button_down.connect(_on_sprint_down)
	btn_sprint.button_up.connect(_on_sprint_up)
	
	btn_pausa.pressed.connect(_on_pausa_pressed)
	btn_continuar.pressed.connect(_on_continuar_pressed)
	btn_reiniciar.pressed.connect(_on_reiniciar_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)


func _conectar_game_manager() -> void:
	if GameManager:
		GameManager.marcador_actualizado.connect(_on_marcador_actualizado)
		GameManager.tiempo_actualizado.connect(_on_tiempo_actualizado)
		_on_marcador_actualizado(GameManager.goles_local, GameManager.goles_visitante)
		label_tiempo.text = GameManager.obtener_tiempo_formateado()


# ==============================================================================
# SISTEMA DE CARGA DE POTENCIA (TOUCH Y TECLADO)
# ==============================================================================

func _procesar_carga_potencia(delta: float) -> void:
	if _accion_cargando != "":
		_potencia_acumulada = clampf(_potencia_acumulada + delta * _velocidad_carga, 0.0, 1.0)
		if barra_potencia:
			barra_potencia.visible = true
			barra_potencia.value = _potencia_acumulada
	else:
		if barra_potencia and barra_potencia.visible:
			barra_potencia.visible = false
			barra_potencia.value = 0.0


func _procesar_input_teclado_carga() -> void:
	# Soporte de carga por teclado (Espacio = Tiro/Entrada, X = Pase/Cambio, C = Hueco/Presión)
	var espacio_presionado: bool = Input.is_key_pressed(KEY_SPACE)
	var x_presionado: bool = Input.is_key_pressed(KEY_X)
	var c_presionado: bool = Input.is_key_pressed(KEY_C)
	
	# Tecla Espacio
	if espacio_presionado and not _tecla_espacio_mantenida:
		_tecla_espacio_mantenida = true
		_on_tiro_down()
	elif not espacio_presionado and _tecla_espacio_mantenida:
		_tecla_espacio_mantenida = false
		_on_tiro_up()
		
	# Tecla X
	if x_presionado and not _tecla_x_mantenida:
		_tecla_x_mantenida = true
		_on_pase_down()
	elif not x_presionado and _tecla_x_mantenida:
		_tecla_x_mantenida = false
		_on_pase_up()
		
	# Tecla C
	if c_presionado and not _tecla_c_mantenida:
		_tecla_c_mantenida = true
		_on_hueco_down()
	elif not c_presionado and _tecla_c_mantenida:
		_tecla_c_mantenida = false
		_on_hueco_up()


func _on_tiro_down() -> void:
	if _modo_defensivo_actual:
		# En defensa, la entrada se ejecuta inmediatamente para máxima respuesta
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_principal_presionada(1.0)
		return
	
	_accion_cargando = "TIRO"
	_potencia_acumulada = 0.15


func _on_tiro_up() -> void:
	if _accion_cargando == "TIRO":
		var pot: float = _potencia_acumulada
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_principal_presionada(pot)


func _on_pase_down() -> void:
	if _modo_defensivo_actual:
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_pase_presionada(1.0)
		return
	
	_accion_cargando = "PASE"
	_potencia_acumulada = 0.15


func _on_pase_up() -> void:
	if _accion_cargando == "PASE":
		var pot: float = _potencia_acumulada
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_pase_presionada(pot)


func _on_hueco_down() -> void:
	if _modo_defensivo_actual:
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_hueco_presionada(1.0)
		return
	
	_accion_cargando = "HUECO"
	_potencia_acumulada = 0.15


func _on_hueco_up() -> void:
	if _accion_cargando == "HUECO":
		var pot: float = _potencia_acumulada
		_accion_cargando = ""
		_potencia_acumulada = 0.0
		var jugador: Jugador3D = _actualizar_jugador_activo()
		if jugador and is_instance_valid(jugador):
			jugador.accion_hueco_presionada(pot)


func _on_sprint_down() -> void:
	var jugador: Jugador3D = _actualizar_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_sprint(true)


func _on_sprint_up() -> void:
	var jugador: Jugador3D = _actualizar_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_sprint(false)


# ==============================================================================
# JOYSTICK VIRTUAL MULTITÁCTIL
# ==============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event
		if touch_event.pressed:
			var pos_local: Vector2 = joystick_base.get_global_transform().affine_inverse() * touch_event.position
			if pos_local.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.5:
				_tocando_joystick = true
				_joystick_touch_id = touch_event.index
				_actualizar_pomo(pos_local)
		elif touch_event.index == _joystick_touch_id:
			_soltar_joystick()
			
	elif event is InputEventScreenDrag and _tocando_joystick:
		var drag_event: InputEventScreenDrag = event
		if drag_event.index == _joystick_touch_id:
			var pos_local: Vector2 = joystick_base.get_global_transform().affine_inverse() * drag_event.position
			_actualizar_pomo(pos_local)
			
	elif event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				var pos_local: Vector2 = joystick_base.get_global_transform().affine_inverse() * mouse_event.position
				if pos_local.distance_to(_centro_joystick) <= _radio_maximo_joystick * 1.5:
					_tocando_joystick = true
					_actualizar_pomo(pos_local)
			else:
				_soltar_joystick()
				
	elif event is InputEventMouseMotion and _tocando_joystick:
		var motion_event: InputEventMouseMotion = event
		var pos_local: Vector2 = joystick_base.get_global_transform().affine_inverse() * motion_event.position
		_actualizar_pomo(pos_local)


func _actualizar_pomo(pos_local: Vector2) -> void:
	var vector_desplazamiento: Vector2 = pos_local - _centro_joystick
	var distancia: float = vector_desplazamiento.length()
	
	if distancia > _radio_maximo_joystick:
		vector_desplazamiento = vector_desplazamiento.normalized() * _radio_maximo_joystick
	
	joystick_pomo.position = _centro_joystick + vector_desplazamiento - (joystick_pomo.size * 0.5)
	
	var direccion_normalizada: Vector2 = vector_desplazamiento / _radio_maximo_joystick
	var jugador: Jugador3D = _actualizar_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_direccion_virtual(direccion_normalizada)


func _soltar_joystick() -> void:
	_tocando_joystick = false
	_joystick_touch_id = -1
	_resetear_joystick()
	var jugador: Jugador3D = _actualizar_jugador_activo()
	if jugador and is_instance_valid(jugador):
		jugador.establecer_direccion_virtual(Vector2.ZERO)


func _resetear_joystick() -> void:
	joystick_pomo.position = _centro_joystick - (joystick_pomo.size * 0.5)


# Handlers de marcador y tiempo
func _on_marcador_actualizado(goles_loc: int, goles_vis: int) -> void:
	if label_marcador:
		label_marcador.text = "%d - %d" % [goles_loc, goles_vis]


func _on_tiempo_actualizado(mins: int, segs: int) -> void:
	if label_tiempo:
		label_tiempo.text = "%02d:%02d" % [mins, segs]


# Handlers del menú de pausa
func _on_pausa_pressed() -> void:
	get_tree().paused = true
	menu_pausa.visible = true


func _on_continuar_pressed() -> void:
	menu_pausa.visible = false
	get_tree().paused = false


func _on_reiniciar_pressed() -> void:
	menu_pausa.visible = false
	GameManager.reiniciar_partido()


func _on_salir_pressed() -> void:
	menu_pausa.visible = false
	GameManager.ir_al_menu_principal()
