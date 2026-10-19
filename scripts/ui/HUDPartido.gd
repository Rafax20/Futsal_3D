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

var _jugador_referencia: Jugador3D = null
var _gestor_partido: GestorPartido = null
var _tiempo_anuncio: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("hud_partido")
	
	if GameManager and not GameManager.partido_en_curso:
		GameManager.iniciar_partido()
	
	_configurar_info_equipos_futsal_3d()
	_conectar_botones_superiores()
	_conectar_game_manager()
	_conectar_gestor_partido()
	
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
	if _gestor_partido and not _gestor_partido.cuenta_regresiva_4s_actualizada.is_connected(_on_cuenta_4s_actualizada):
		_gestor_partido.cuenta_regresiva_4s_actualizada.connect(_on_cuenta_4s_actualizada)


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
