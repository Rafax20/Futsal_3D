class_name HUDPartido
extends CanvasLayer

## Interfaz de partido móvil estilo FC Mobile / eFootball.
## Orquesta el marcador reglamentario de fútsal (reloj neto, faltas acumuladas, cuenta de 4s, tiempo muerto),
## ficha de jugador activo, anuncios de transmisión, menú modal de pausa y el nodo desacoplado
## de controles táctiles contextuales (`TouchControls.gd` en `$MargenControles`).

@export var ruta_jugador: NodePath = ^"../Jugadores/Local_Pivot"

# Referencia al módulo desacoplado de controles táctiles (Ataque/Defensa + Gestos Swipe)
@onready var touch_controls: TouchControls = $MargenControles as TouchControls

# Referencias al marcador, escudos, faltas acumuladas, periodo, ficha de jugador y anuncios
@onready var escudo_local: ColorRect = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/EscudoLocal") as ColorRect
@onready var label_local: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelLocal") as Label
@onready var label_faltas_local: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelFaltasLocal") as Label
@onready var label_marcador: Label = $MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelGoles
@onready var label_faltas_vis: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelFaltasVis") as Label
@onready var label_vis: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelVis") as Label
@onready var escudo_vis: ColorRect = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/EscudoVis") as ColorRect
@onready var label_periodo: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelPeriodo") as Label
@onready var label_tiempo: Label = $MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelTiempo
@onready var label_cuenta_4s: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelCuenta4s") as Label
@onready var label_sancion_2min: Label = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador/LabelSancion2Min") as Label
@onready var label_jugador_activo: Label = get_node_or_null("PanelFichaJugador/LabelJugadorActivo") as Label
@onready var btn_tiempo_muerto: Button = get_node_or_null("BotonTiempoMuerto") as Button
@onready var btn_pausa: Button = $BotonPausa
@onready var banner_anuncio: PanelContainer = $BannerAnuncio
@onready var label_anuncio: Label = $BannerAnuncio/LabelAnuncio

# Referencias al menú de pausa
@onready var menu_pausa: Control = $MenuPausaModal
@onready var btn_continuar: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonContinuar
@onready var btn_reiniciar: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonReiniciar
@onready var btn_salir: Button = $MenuPausaModal/PanelModal/VBoxBotones/BotonSalir

signal omitir_cinematica_solicitada

# Elementos dinámicos de cinemática de faltas, repetición y botón omitir
var btn_omitir: Button = null
var panel_tarjeta: PanelContainer = null
var label_titulo_tarjeta: Label = null
var label_jugador_tarjeta: Label = null
var label_motivo_tarjeta: Label = null
var badge_repeticion: PanelContainer = null

var _jugador_referencia: Jugador3D = null
var _gestor_partido: GestorPartido = null
var _tiempo_anuncio: float = 0.0
var _sancion_activa_loc: bool = false
var _tiempo_sancion_loc: float = 0.0
var _sancion_activa_vis: bool = false
var _tiempo_sancion_vis: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud_partido")
	
	if GameManager and not GameManager.partido_en_curso:
		GameManager.iniciar_partido()
	
	_configurar_info_equipos_futsal_3d()
	_conectar_botones_superiores()
	_inicializar_ui_cinematica_falta()
	_conectar_game_manager()
	_conectar_gestor_partido()
	_conectar_eventos_atajadas()
	
	menu_pausa.visible = false
	if banner_anuncio:
		banner_anuncio.visible = false


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


func _physics_process(delta: float) -> void:
	_gestionar_temporizador_anuncio(delta)
	_actualizar_ficha_jugador_activo()
	_actualizar_estado_boton_tiempo_muerto()


func _gestionar_temporizador_anuncio(delta: float) -> void:
	if _tiempo_anuncio > 0.0:
		_tiempo_anuncio -= delta
		if _tiempo_anuncio <= 0.0 and banner_anuncio:
			banner_anuncio.visible = false


## Muestra un banner llamativo estilo transmisión (ej: "¡SAQUE DE BANDA!", "¡PASA Y CORRE!")
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
		var sufijo_estado: String = ""
		if jugador.tiene_balon_en_manos:
			sufijo_estado = "  •  [SAQUE CON LA MANO]"
		elif jugador._en_posicion_saque:
			if _gestor_partido and _gestor_partido.es_saque_centro_activo():
				sufijo_estado = "  •  [SAQUE DE CENTRO]"
			else:
				sufijo_estado = "  •  [SAQUE DETENIDO]"
		label_jugador_activo.text = "#%d %s [%s]  •  OVR %d%s" % [
			jugador.dorsal,
			jugador.nombre_jugador if jugador.nombre_jugador != "" else jugador.posicion_tactica,
			jugador.siglas_equipo,
			jugador.get_media_ovr(),
			sufijo_estado
		]


## Habilita el botón de Tiempo Muerto únicamente cuando el equipo local posee el balón y tiene su tiempo muerto disponible
func _actualizar_estado_boton_tiempo_muerto() -> void:
	if btn_tiempo_muerto == null:
		return
	if _gestor_partido == null:
		_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	
	var disponible_periodo: bool = GameManager.puede_pedir_tiempo_muerto(0) if GameManager else false
	var tiene_posesion_local: bool = _gestor_partido.equipo_posee_balon(0) if _gestor_partido else false
	
	btn_tiempo_muerto.disabled = not (disponible_periodo and tiene_posesion_local)
	btn_tiempo_muerto.modulate = Color(1.0, 1.0, 1.0, 1.0) if not btn_tiempo_muerto.disabled else Color(0.55, 0.55, 0.55, 0.65)
	btn_tiempo_muerto.text = "⏱ T.M." if disponible_periodo else "T.M. USADO"


func _actualizar_jugador_activo() -> Jugador3D:
	if touch_controls != null:
		var j_tc: Jugador3D = touch_controls.obtener_jugador_activo()
		if j_tc != null:
			_jugador_referencia = j_tc
			return _jugador_referencia
	
	if _jugador_referencia != null and is_instance_valid(_jugador_referencia) and _jugador_referencia.es_controlado:
		return _jugador_referencia
	
	var activos: Array[Node] = get_tree().get_nodes_in_group("jugador_activo")
	if not activos.is_empty():
		_jugador_referencia = activos[0] as Jugador3D
		return _jugador_referencia
	
	if has_node(ruta_jugador):
		_jugador_referencia = get_node(ruta_jugador) as Jugador3D
		return _jugador_referencia
	
	return null


func _conectar_botones_superiores() -> void:
	if btn_tiempo_muerto:
		btn_tiempo_muerto.pressed.connect(_on_tiempo_muerto_pressed)
	btn_pausa.pressed.connect(_on_pausa_pressed)
	btn_continuar.pressed.connect(_on_continuar_pressed)
	btn_reiniciar.pressed.connect(_on_reiniciar_pressed)
	btn_salir.pressed.connect(_on_salir_pressed)


func _conectar_game_manager() -> void:
	if GameManager:
		GameManager.marcador_actualizado.connect(_on_marcador_actualizado)
		GameManager.tiempo_actualizado.connect(_on_tiempo_actualizado)
		if GameManager.has_signal("faltas_actualizadas"):
			GameManager.faltas_actualizadas.connect(_on_faltas_actualizadas)
		if GameManager.has_signal("periodo_cambiado"):
			GameManager.periodo_cambiado.connect(_on_periodo_cambiado)
		_on_marcador_actualizado(GameManager.goles_local, GameManager.goles_visitante)
		_on_faltas_actualizadas(GameManager.faltas_local, GameManager.faltas_visitante)
		_on_periodo_cambiado(GameManager.periodo_actual)
		label_tiempo.text = GameManager.obtener_tiempo_formateado()


func _conectar_gestor_partido() -> void:
	_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	if _gestor_partido:
		if not _gestor_partido.cuenta_regresiva_4s_actualizada.is_connected(_on_cuenta_4s_actualizada):
			_gestor_partido.cuenta_regresiva_4s_actualizada.connect(_on_cuenta_4s_actualizada)
		if not _gestor_partido.sancion_2min_actualizada.is_connected(_on_sancion_2min_actualizada):
			_gestor_partido.sancion_2min_actualizada.connect(_on_sancion_2min_actualizada)


# Handlers de marcador, tiempo neto, faltas acumuladas, periodo y 4 segundos
func _on_marcador_actualizado(goles_loc: int, goles_vis: int) -> void:
	if label_marcador:
		label_marcador.text = "%d - %d" % [goles_loc, goles_vis]


func _on_tiempo_actualizado(mins: int, segs: int) -> void:
	if label_tiempo:
		label_tiempo.text = "%02d:%02d" % [mins, segs]


func _on_faltas_actualizadas(faltas_loc: int, faltas_vis: int) -> void:
	if label_faltas_local:
		label_faltas_local.text = "F:%d" % faltas_loc
		label_faltas_local.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if faltas_loc >= 5 else Color(0.95, 0.65, 0.25))
	if label_faltas_vis:
		label_faltas_vis.text = "F:%d" % faltas_vis
		label_faltas_vis.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if faltas_vis >= 5 else Color(0.95, 0.65, 0.25))


func _on_periodo_cambiado(periodo: int) -> void:
	if label_periodo:
		label_periodo.text = "%dT" % periodo


func _on_cuenta_4s_actualizada(segundos_restantes: float, activa: bool) -> void:
	if label_cuenta_4s:
		label_cuenta_4s.visible = activa
		if activa:
			label_cuenta_4s.text = "[%.1fs]" % segundos_restantes


func _on_sancion_2min_actualizada(equipo_sancionado: int, segundos_restantes: float, activa: bool) -> void:
	if equipo_sancionado == 0:
		_sancion_activa_loc = activa
		_tiempo_sancion_loc = segundos_restantes
	else:
		_sancion_activa_vis = activa
		_tiempo_sancion_vis = segundos_restantes
	
	if label_sancion_2min == null:
		var contenedor_marcador: Node = get_node_or_null("MarcadorSuperior/PanelContenedor/ContenedorMarcador")
		if contenedor_marcador:
			label_sancion_2min = Label.new()
			label_sancion_2min.name = "LabelSancion2Min"
			label_sancion_2min.visible = false
			label_sancion_2min.add_theme_color_override("font_color", Color(1.0, 0.28, 0.28, 1.0))
			label_sancion_2min.add_theme_font_size_override("font_size", 13)
			contenedor_marcador.add_child(label_sancion_2min)
	
	if label_sancion_2min == null:
		return
	
	if _sancion_activa_loc and _sancion_activa_vis:
		label_sancion_2min.visible = true
		var mins_l: int = int(_tiempo_sancion_loc) / 60
		var segs_l: int = int(_tiempo_sancion_loc) % 60
		var mins_v: int = int(_tiempo_sancion_vis) / 60
		var segs_v: int = int(_tiempo_sancion_vis) % 60
		label_sancion_2min.text = "[4v4 L:%02d:%02d V:%02d:%02d]" % [mins_l, segs_l, mins_v, segs_v]
	elif _sancion_activa_loc:
		label_sancion_2min.visible = true
		var mins: int = int(_tiempo_sancion_loc) / 60
		var segs: int = int(_tiempo_sancion_loc) % 60
		label_sancion_2min.text = "[4v5 LOC %02d:%02d]" % [mins, segs]
	elif _sancion_activa_vis:
		label_sancion_2min.visible = true
		var mins: int = int(_tiempo_sancion_vis) / 60
		var segs: int = int(_tiempo_sancion_vis) % 60
		label_sancion_2min.text = "[4v5 VIS %02d:%02d]" % [mins, segs]
	else:
		label_sancion_2min.visible = false


func _conectar_eventos_atajadas() -> void:
	var balones: Array[Node] = get_tree().get_nodes_in_group("balon")
	if not balones.is_empty():
		var b: Balon3D = balones[0] as Balon3D
		if b and not b.atajada_realizada.is_connected(_on_atajada_realizada):
			b.atajada_realizada.connect(_on_atajada_realizada)


func _on_atajada_realizada(zona: String, nombre_arquero: String) -> void:
	var mensaje: String = ""
	match zona:
		"atrapada":
			mensaje = "¡PARADÓN Y BALÓN ASEGURADO!"
		"manos", "antebrazos":
			mensaje = "¡DESVÍO CON LA MANO DE %s!" % nombre_arquero
		"pecho", "cabeza":
			mensaje = "¡BLOQUEO DE PECHO DE %s!" % nombre_arquero
		"cruz":
			mensaje = "¡ACHIQUE EN CRUZ DE %s!" % nombre_arquero
		"piernas":
			mensaje = "¡PARADA CON EL PIE DE %s!" % nombre_arquero
		_:
			mensaje = "¡DESVÍO DEL ARQUERO!"
	mostrar_anuncio(mensaje, 2.0)


func _on_tiempo_muerto_pressed() -> void:
	if _gestor_partido == null:
		_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	if _gestor_partido:
		_gestor_partido.solicitar_tiempo_muerto(0)


# Handlers del menú de pausa
func _on_pausa_pressed() -> void:
	get_tree().paused = true
	menu_pausa.visible = true
	if touch_controls:
		touch_controls.visible = false


func _on_continuar_pressed() -> void:
	menu_pausa.visible = false
	if touch_controls:
		touch_controls.visible = true
	get_tree().paused = false


func _on_reiniciar_pressed() -> void:
	menu_pausa.visible = false
	GameManager.reiniciar_partido()


func _on_salir_pressed() -> void:
	menu_pausa.visible = false
	GameManager.ir_al_menu_principal()


# ==============================================================================
# UI DE CINEMÁTICA DE FALTAS, TARJETAS, REPETICIÓN Y BOTÓN OMITIR
# ==============================================================================

func _inicializar_ui_cinematica_falta() -> void:
	# 1. Botón "OMITIR ⏭" táctil estilo eFootball
	btn_omitir = Button.new()
	btn_omitir.name = "BotonOmitirCinematica"
	btn_omitir.text = "OMITIR ⏭"
	btn_omitir.visible = false
	btn_omitir.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn_omitir.anchor_left = 1.0
	btn_omitir.anchor_top = 1.0
	btn_omitir.anchor_right = 1.0
	btn_omitir.anchor_bottom = 1.0
	btn_omitir.offset_left = -175.0
	btn_omitir.offset_top = -80.0
	btn_omitir.offset_right = -25.0
	btn_omitir.offset_bottom = -30.0
	
	var style_omitir: StyleBoxFlat = StyleBoxFlat.new()
	style_omitir.bg_color = Color(0.08, 0.12, 0.18, 0.90)
	style_omitir.border_width_left = 2
	style_omitir.border_width_top = 2
	style_omitir.border_width_right = 2
	style_omitir.border_width_bottom = 2
	style_omitir.border_color = Color(0.25, 0.75, 1.0, 0.85)
	style_omitir.corner_radius_top_left = 20
	style_omitir.corner_radius_top_right = 20
	style_omitir.corner_radius_bottom_right = 20
	style_omitir.corner_radius_bottom_left = 20
	btn_omitir.add_theme_stylebox_override("normal", style_omitir)
	btn_omitir.add_theme_stylebox_override("hover", style_omitir)
	btn_omitir.add_theme_stylebox_override("pressed", style_omitir)
	btn_omitir.add_theme_font_size_override("font_size", 14)
	btn_omitir.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	btn_omitir.pressed.connect(_on_boton_omitir_pressed)
	add_child(btn_omitir)

	# 2. Placa de Amonestación / Sanción Disciplinaria (Tarjeta Amarilla / Roja)
	panel_tarjeta = PanelContainer.new()
	panel_tarjeta.name = "PanelTarjetaCinematica"
	panel_tarjeta.visible = false
	panel_tarjeta.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel_tarjeta.anchor_left = 0.5
	panel_tarjeta.anchor_right = 0.5
	panel_tarjeta.anchor_top = 0.14
	panel_tarjeta.anchor_bottom = 0.14
	panel_tarjeta.offset_left = -220.0
	panel_tarjeta.offset_top = 0.0
	panel_tarjeta.offset_right = 220.0
	panel_tarjeta.offset_bottom = 90.0

	var style_tarjeta: StyleBoxFlat = StyleBoxFlat.new()
	style_tarjeta.bg_color = Color(0.06, 0.08, 0.12, 0.94)
	style_tarjeta.border_width_left = 2
	style_tarjeta.border_width_top = 2
	style_tarjeta.border_width_right = 2
	style_tarjeta.border_width_bottom = 2
	style_tarjeta.border_color = Color(0.35, 0.45, 0.65, 0.90)
	style_tarjeta.corner_radius_top_left = 12
	style_tarjeta.corner_radius_top_right = 12
	style_tarjeta.corner_radius_bottom_right = 12
	style_tarjeta.corner_radius_bottom_left = 12
	style_tarjeta.content_margin_left = 16.0
	style_tarjeta.content_margin_right = 16.0
	style_tarjeta.content_margin_top = 8.0
	style_tarjeta.content_margin_bottom = 8.0
	panel_tarjeta.add_theme_stylebox_override("panel", style_tarjeta)

	var vbox_t: VBoxContainer = VBoxContainer.new()
	vbox_t.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox_t.add_theme_constant_override("separation", 2)
	panel_tarjeta.add_child(vbox_t)

	label_titulo_tarjeta = Label.new()
	label_titulo_tarjeta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_titulo_tarjeta.add_theme_font_size_override("font_size", 16)
	label_titulo_tarjeta.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	vbox_t.add_child(label_titulo_tarjeta)

	label_jugador_tarjeta = Label.new()
	label_jugador_tarjeta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_jugador_tarjeta.add_theme_font_size_override("font_size", 14)
	label_jugador_tarjeta.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	vbox_t.add_child(label_jugador_tarjeta)

	label_motivo_tarjeta = Label.new()
	label_motivo_tarjeta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label_motivo_tarjeta.add_theme_font_size_override("font_size", 12)
	label_motivo_tarjeta.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88))
	vbox_t.add_child(label_motivo_tarjeta)

	add_child(panel_tarjeta)

	# 3. Insignia sutil de Repetición (Badge REPLAY)
	badge_repeticion = PanelContainer.new()
	badge_repeticion.name = "BadgeRepeticion"
	badge_repeticion.visible = false
	badge_repeticion.set_anchors_preset(Control.PRESET_TOP_LEFT)
	badge_repeticion.anchor_left = 0.0
	badge_repeticion.anchor_top = 0.075
	badge_repeticion.anchor_right = 0.0
	badge_repeticion.anchor_bottom = 0.075
	badge_repeticion.offset_left = 24.0
	badge_repeticion.offset_top = 0.0
	badge_repeticion.offset_right = 160.0
	badge_repeticion.offset_bottom = 32.0

	var style_rep: StyleBoxFlat = StyleBoxFlat.new()
	style_rep.bg_color = Color(0.85, 0.15, 0.15, 0.88)
	style_rep.corner_radius_top_left = 8
	style_rep.corner_radius_top_right = 8
	style_rep.corner_radius_bottom_right = 8
	style_rep.corner_radius_bottom_left = 8
	style_rep.content_margin_left = 10.0
	style_rep.content_margin_right = 10.0
	style_rep.content_margin_top = 4.0
	style_rep.content_margin_bottom = 4.0
	badge_repeticion.add_theme_stylebox_override("panel", style_rep)

	var lbl_rep: Label = Label.new()
	lbl_rep.text = "▶ REPETICIÓN"
	lbl_rep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_rep.add_theme_font_size_override("font_size", 13)
	lbl_rep.add_theme_color_override("font_color", Color.WHITE)
	badge_repeticion.add_child(lbl_rep)
	add_child(badge_repeticion)


## Muestra u oculta el botón "OMITIR ⏭"
func mostrar_boton_omitir(mostrar: bool) -> void:
	if btn_omitir:
		btn_omitir.visible = mostrar


## Muestra la placa de sanción con los datos del jugador amonestado
func mostrar_placa_tarjeta(
	infractor: Jugador3D,
	tipo_tarjeta: String,
	puntaje: float,
	desglose: Array = []
) -> void:
	if panel_tarjeta == null:
		return
	
	var titulo_texto: String = "¡TARJETA AMARILLA!"
	var col_titulo: Color = Color(1.0, 0.85, 0.1)
	if tipo_tarjeta == "ROJA_DIRECTA":
		titulo_texto = "¡TARJETA ROJA DIRECTA! — EXPULSIÓN"
		col_titulo = Color(0.95, 0.15, 0.15)
	elif tipo_tarjeta == "SEGUNDA_AMARILLA":
		titulo_texto = "¡SEGUNDA AMARILLA! — EXPULSIÓN"
		col_titulo = Color(0.95, 0.35, 0.15)
	
	var nombre: String = "Jugador"
	var dorsal_j: int = 10
	var siglas: String = "RFC"
	var pos_tac: String = "PIVOT"
	if infractor != null:
		nombre = infractor.nombre_jugador if infractor.nombre_jugador != "" else infractor.posicion_tactica
		dorsal_j = infractor.dorsal
		siglas = infractor.siglas_equipo
		pos_tac = infractor.posicion_tactica
	
	var detalle_motivo: String = "Infracción reglamentaria (Severidad: %.1f)" % puntaje
	if not desglose.is_empty():
		detalle_motivo = "%s (Severidad: %.1f)" % [str(desglose[0]), puntaje]
	
	if label_titulo_tarjeta:
		label_titulo_tarjeta.text = titulo_texto
		label_titulo_tarjeta.add_theme_color_override("font_color", col_titulo)
	if label_jugador_tarjeta:
		label_jugador_tarjeta.text = "#%d %s [%s] • %s" % [dorsal_j, nombre, siglas, pos_tac]
	if label_motivo_tarjeta:
		label_motivo_tarjeta.text = detalle_motivo
	
	panel_tarjeta.visible = true
	panel_tarjeta.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var tw: Tween = create_tween().set_ignore_time_scale(true)
	tw.tween_property(panel_tarjeta, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)


## Oculta la placa de amonestación
func ocultar_placa_tarjeta() -> void:
	if panel_tarjeta and panel_tarjeta.visible:
		var tw: Tween = create_tween().set_ignore_time_scale(true)
		tw.tween_property(panel_tarjeta, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			if panel_tarjeta:
				panel_tarjeta.visible = false
		)


## Muestra u oculta la insignia de repetición en pantalla
func mostrar_indicador_repeticion(mostrar: bool) -> void:
	if badge_repeticion:
		badge_repeticion.visible = mostrar


func _on_boton_omitir_pressed() -> void:
	omitir_cinematica_solicitada.emit()
	if _gestor_partido == null:
		_gestor_partido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	if _gestor_partido and _gestor_partido.has_method("omitir_secuencia_falta"):
		_gestor_partido.call("omitir_secuencia_falta")

