class_name EntrenamientoTiroLibre
extends Node3D

## Modo de Entrenamiento de Tiro Libre estilo eFootball Mobile.
## Orquesta el flujo continuo e iterativo:
## 1. SELECCION_POSICION: Vista cenital sobre el medio campo ofensivo; arrastre táctil del balón
##    (`InputEventScreenDrag` / ratón) restringido a los límites reglamentarios y botón "Confirmar".
## 2. EJECUCION: Transición suave de cámara a perspectiva trasera baja (`CamaraTransmision`),
##    posicionamiento del lanzador, barrera rival a 5.0m y arquero bajo palos; disparo por trazo
##    táctil (Swipe) con potencia, elevación y efecto Magnus (`Balon3D.liberar_tiro_libre_swipe`),
##    y botones auxiliares ("Cambiar vista", "Elegir lanzador", "Cambio de posición").
## 3. TRANSICION_FADE: Detección automática de fin de jugada (gol, línea de fondo, banda, desvío/freno
##    < 0.5 m/s o 2.5s post-impacto) con fundido a negro (`ColorRect` + `Tween`) para reiniciar el ciclo.

enum EstadoEntrenamiento {
	SELECCION_POSICION,
	EJECUCION,
	JUEGO_ACTIVO,
	TRANSICION_FADE
}

const ESCENA_JUGADOR_3D: PackedScene = preload("res://scenes/Jugador3D.tscn")

signal cuenta_regresiva_4s_actualizada(segundos_restantes: float, activa: bool)

@export_group("Límites Reglamentarios de Selección (Medio Campo Ofensivo)")
## Límite mínimo en X (línea central hacia campo rival).
@export var min_x_seleccion: float = 1.5
## Límite máximo en X (fuera del área penal de 6m que empieza en X = 14.0).
@export var max_x_seleccion: float = 13.8
## Límite lateral en Z (dentro de las bandas de ±10.0m).
@export var max_z_seleccion: float = 8.8
## Distancia reglamentaria de la barrera de futsal (5.0 metros).
@export var distancia_barrera: float = 5.0
## Radio del balón de fútsal ajustado anatómicamente al calzado (0.143 m para contacto perfecto con el parqué a Y = 0).
@export var radio_balon: float = 0.143
## Distancia fija de aproximación del pateador detrás del balón (1.5 metros).
@export var distancia_aproximacion_pateador: float = 1.5

@export_group("Reglas Oficiales FIFA/IFAB de Tiro Libre")
## Tiempo máximo reglamentario (segundos) para ejecutar el saque una vez autorizado.
@export var tiempo_saque: float = 4.0
## Indica si el tiro libre actual es indirecto (requiere al menos 2 toques antes de entrar al arco).
@export var es_tiro_indirecto: bool = false
## Cantidad de faltas acumuladas del rival (>= 6 activa Tiro Libre sin Barrera / Doble Penalti a 10m).
@export var faltas_acumuladas: int = 1

@export_group("Modo de Juego")
## En modo entrenamiento libre se desactiva el temporizador de 4s y se respeta la posición elegida de forma indefinida.
@export var es_modo_entrenamiento: bool = true

@export_group("Tiempos y Umbrales de Fin de Jugada")
## Velocidad lineal mínima (m/s) tras desvío/impacto para dar por concluida la jugada.
@export var umbral_velocidad_detencion: float = 0.5
## Tiempo máximo (segundos) desde que se patea el balón hasta reiniciar la jugada.
@export var tiempo_maximo_jugada: float = 2.5
## Duración (segundos) del fundido a negro (fade in / fade out).
@export var duracion_fade: float = 0.38

# Referencias a nodos 3D de la escena
@onready var camara: CamaraTransmision = $Camera3D as CamaraTransmision
@onready var balon: Balon3D = $Balon3D as Balon3D
@onready var contenedor_jugadores: Node3D = $Jugadores as Node3D
@onready var indicador_circulo_verde: Node3D = $IndicadorPosicionBalon as Node3D
@onready var area_gol_der: Area3D = ($PorteriaDerecha/GoalTrigger if has_node("PorteriaDerecha/GoalTrigger") else get_node_or_null("AreaGolDerecha")) as Area3D
@onready var timer_saque_4s: Timer = get_node_or_null("TimerSaque4s") as Timer

# Referencias a jugadores en escena
@onready var lanzador: Jugador3D = $Jugadores/Local_Pivot as Jugador3D
@onready var portero_rival: Jugador3D = $Jugadores/Vis_Portero as Jugador3D
@onready var def_barrera_1: Jugador3D = $Jugadores/Vis_Cierre as Jugador3D
@onready var def_barrera_2: Jugador3D = $Jugadores/Vis_AlaIzq as Jugador3D
@onready var def_barrera_3: Jugador3D = $Jugadores/Vis_AlaDer as Jugador3D
@onready var companero_banda: Jugador3D = get_node_or_null("Jugadores/Companero_Banda") as Jugador3D
@onready var companero_frontal: Jugador3D = get_node_or_null("Jugadores/Companero_Frontal") as Jugador3D

## Umbral de distancia a portería (m):
## Si la falta ocurre a > 15.0m, la vista por defecto es la táctica/cenital (orientada a la creación de juego).
## Si la falta está a <= 15.0m, la vista por defecto es la trasera OTS (con interfaz táctil de trazo de tiro curvo).
@export var umbral_distancia_remate: float = 15.0

# Referencias a la interfaz de usuario (CanvasLayer)
@onready var capa_trazo_swipe: Control = $UIEntrenamiento/CapaTrazoSwipe as Control
@onready var panel_seleccion: Control = $UIEntrenamiento/PanelSeleccionPosicion as Control
@onready var btn_confirmar: Button = $UIEntrenamiento/PanelSeleccionPosicion/BotonConfirmar as Button
@onready var label_coord_seleccion: Label = $UIEntrenamiento/PanelSeleccionPosicion/PanelInstruccion/LabelInstruccion as Label

@onready var panel_ejecucion: Control = $UIEntrenamiento/PanelEjecucionTiroLibre as Control
@onready var touch_controls: TouchControls = get_node_or_null("UIEntrenamiento/TouchControls") as TouchControls

@onready var btn_cambiar_vista: Button = $UIEntrenamiento/PanelEjecucionTiroLibre/ContenedorBotonesAux/BotonCambiarVista as Button
@onready var btn_elegir_lanzador: Button = $UIEntrenamiento/PanelEjecucionTiroLibre/ContenedorBotonesAux/BotonElegirLanzador as Button
@onready var btn_cambio_posicion: Button = $UIEntrenamiento/PanelEjecucionTiroLibre/ContenedorBotonesAux/BotonCambioPosicion as Button
@onready var label_guia_swipe: Label = $UIEntrenamiento/PanelEjecucionTiroLibre/LabelGuiaSwipe as Label
@onready var barra_potencia_swipe: ProgressBar = get_node_or_null("UIEntrenamiento/PanelEjecucionTiroLibre/BarraPotenciaSwipe") as ProgressBar
@onready var panel_cuenta_4s: Control = get_node_or_null("UIEntrenamiento/PanelEjecucionTiroLibre/PanelCuenta4s") as Control
@onready var label_cuenta_4s: Label = get_node_or_null("UIEntrenamiento/PanelEjecucionTiroLibre/PanelCuenta4s/VBoxCuenta4s/LabelCuenta4s") as Label
@onready var barra_cuenta_4s: ProgressBar = get_node_or_null("UIEntrenamiento/PanelEjecucionTiroLibre/PanelCuenta4s/VBoxCuenta4s/BarraCuenta4s") as ProgressBar

@onready var btn_salir_menu: Button = $UIEntrenamiento/BarraSuperior/BotonSalir as Button
@onready var btn_modo_regla: Button = get_node_or_null("UIEntrenamiento/BarraSuperior/BotonModoRegla") as Button
@onready var label_resultado: Label = $UIEntrenamiento/BannerResultado/LabelResultado as Label
@onready var banner_resultado: PanelContainer = $UIEntrenamiento/BannerResultado as PanelContainer
@onready var rect_fade: ColorRect = $UIEntrenamiento/FadeNegro as ColorRect

# Estado de Continuidad de Juego en Vivo (Live Play) y Posesión
var _tiempo_posesion_defensiva: float = 0.0
var _limite_tiempo_posesion_defensiva: float = 1.5
var _tiempo_sin_movimiento_balon: float = 0.0

# Estado interno del entrenamiento y reglas FIFA/IFAB
var estado_actual: EstadoEntrenamiento = EstadoEntrenamiento.SELECCION_POSICION
var toques_en_jugada: int = 0
var _indice_modo_regla: int = 0
var _reproductor_silbato: AudioStreamPlayer = null
var _pos_falta_seleccionada: Vector3 = Vector3(9.5, 0.0, 0.0)
var _pos_ejecucion_efectiva: Vector3 = Vector3(9.5, 0.0, 0.0)
var _arrastrando_balon: bool = false
var _drag_touch_id: int = -1
var _vista_cenital_alterna: bool = false
var _base_forward_tl: Vector3 = Vector3(1.0, 0.0, 0.0)
var _pos_fija_lanzador: Vector3 = Vector3.ZERO
var _direccion_apuntado_tactico: Vector3 = Vector3(1.0, 0.0, 0.0)
var _indicador_cono_pase: Node3D = null
var _mesh_flecha_pase: MeshInstance3D = null
var _mat_cono_pase: StandardMaterial3D = null

# Estado de ejecución del disparo, carrera previa (~0.35s) y seguimiento post-impacto
var _disparo_realizado: bool = false
var _en_secuencia_carrera_tl: bool = false
var _tiempo_carrera_tl: float = 0.0
var _duracion_carrera_tl: float = 0.35
var _pos_inicio_carrera_tl: Vector3 = Vector3.ZERO
var _pos_impacto_carrera_tl: Vector3 = Vector3.ZERO
var _dir_tiro_pendiente: Vector3 = Vector3(1.0, 0.0, 0.0)
var _impulso_pendiente: Vector3 = Vector3.ZERO
var _comba_pendiente: float = 0.0
var _es_cucharita_pendiente: bool = false
var _tiempo_post_impacto: float = 0.0
var _goles_convertidos: int = 0
var _intentos_totales: int = 0

# Estado de Pantalla Dividida: Zona Izquierda (< 45%) Paneo de Cámara | Zona Derecha (>= 45%) Swipe Disparo
var _pan_touch_id: int = -1
var _pan_pos_previa: Vector2 = Vector2.ZERO
var _pan_pos_inicio: Vector2 = Vector2.ZERO
var _pan_tiempo_inicio: float = 0.0
var _capturando_swipe: bool = false
var _swipe_touch_id: int = -1
var _swipe_puntos: PackedVector2Array = PackedVector2Array()
var _swipe_tiempo_inicio: float = 0.0
var _potencia_swipe_actual: float = 0.0
var _comba_swipe_actual: float = 0.0

# Posiciones ancladas de la barrera actual
var _defensores_barrera: Array[Jugador3D] = []
var _posiciones_barrera: Array[Vector3] = []

# Estado de pase a compañeros (Pase al Pie vs. Pase al Hueco en Profundidad)
enum TipoPaseTL { NINGUNO, PIE, HUECO }
const VEL_PASE_AL_PIE: float = 8.5
const VEL_PASE_AL_HUECO: float = 11.5

var _jugador_activo_actual: Jugador3D = null
var _en_jugada_de_pase: bool = false
var _receptor_pase: Jugador3D = null
var _pase_en_transito: bool = false
var _tiempo_espera_pase: float = 0.0
var _tipo_pase_activo: TipoPaseTL = TipoPaseTL.NINGUNO
var _punto_hueco_objetivo: Vector3 = Vector3.ZERO
var _ultimo_mensaje_atajada: String = ""


## Retorna true si la sesión actual se encuentra en Modo Entrenamiento
func es_entrenamiento_activo() -> bool:
	if es_modo_entrenamiento:
		return true
	if GameManager != null and not GameManager.partido_en_curso:
		return true
	return false


func _ready() -> void:
	add_to_group("entrenamiento_tiro_libre")
	if GameManager:
		GameManager.partido_en_curso = false
		GameManager.reloj_neto_activo = false
	
	_inicializar_silbato_arbitral()
	_inicializar_timer_saque_4s()
	_inicializar_jugadores_entrenamiento()
	_crear_indicador_cono_pase()
	_conectar_senales_ui()
	_actualizar_boton_modo_regla()
	
	if balon:
		if not balon.atajada_realizada.is_connected(_on_atajada_realizada):
			balon.atajada_realizada.connect(_on_atajada_realizada)
		if not balon.bloqueo_barrera_realizado.is_connected(_on_bloqueo_barrera_realizado):
			balon.bloqueo_barrera_realizado.connect(_on_bloqueo_barrera_realizado)
		if not balon.mano_cometida.is_connected(_on_mano_en_barrera):
			balon.mano_cometida.connect(_on_mano_en_barrera)
	
	if area_gol_der and not area_gol_der.body_entered.is_connected(_on_area_gol_derecha_body_entered):
		area_gol_der.body_entered.connect(_on_area_gol_derecha_body_entered)
	
	if capa_trazo_swipe and not capa_trazo_swipe.draw.is_connected(_on_capa_trazo_swipe_draw):
		capa_trazo_swipe.draw.connect(_on_capa_trazo_swipe_draw)
	
	if banner_resultado:
		banner_resultado.visible = false
	if rect_fade:
		rect_fade.color = Color(0.0, 0.0, 0.0, 0.0)
		rect_fade.visible = false
	
	_entrar_estado_seleccion_posicion(true)


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


func _inicializar_timer_saque_4s() -> void:
	if timer_saque_4s == null:
		timer_saque_4s = Timer.new()
		timer_saque_4s.name = "TimerSaque4s"
		add_child(timer_saque_4s)
	timer_saque_4s.wait_time = tiempo_saque
	timer_saque_4s.one_shot = true
	if not timer_saque_4s.timeout.is_connected(_on_timer_saque_4s_timeout):
		timer_saque_4s.timeout.connect(_on_timer_saque_4s_timeout)


## Crea el indicador visual procedural de puntería (flecha de pase en el suelo)
func _crear_indicador_cono_pase() -> void:
	if _indicador_cono_pase != null and is_instance_valid(_indicador_cono_pase):
		return

	_indicador_cono_pase = Node3D.new()
	_indicador_cono_pase.name = "IndicadorConoPase"

	_mat_cono_pase = StandardMaterial3D.new()
	_mat_cono_pase.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_cono_pase.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cono_pase.albedo_color = Color(0.2, 0.85, 1.0, 0.85)
	_mat_cono_pase.cull_mode = BaseMaterial3D.CULL_DISABLED

	var imm: ImmediateMesh = ImmediateMesh.new()
	imm.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mat_cono_pase)

	var w_s: float = 0.16
	var z_start: float = 0.35
	var z_mid: float = 2.2
	var w_h: float = 0.48
	var z_tip: float = 3.2

	# Vertices del fuste (shaft) de la flecha
	var p1: Vector3 = Vector3(-w_s, 0.02, -z_start)
	var p2: Vector3 = Vector3(w_s, 0.02, -z_start)
	var p3: Vector3 = Vector3(w_s, 0.02, -z_mid)
	var p4: Vector3 = Vector3(-w_s, 0.02, -z_mid)

	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p1)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p2)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p3)

	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p1)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p3)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(p4)

	# Vertices de la punta (arrow head)
	var h1: Vector3 = Vector3(-w_h, 0.02, -z_mid)
	var h2: Vector3 = Vector3(w_h, 0.02, -z_mid)
	var h3: Vector3 = Vector3(0.0, 0.02, -z_tip)

	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(h1)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(h2)
	imm.surface_set_normal(Vector3.UP)
	imm.surface_add_vertex(h3)

	imm.surface_end()

	_mesh_flecha_pase = MeshInstance3D.new()
	_mesh_flecha_pase.name = "MeshFlecha"
	_mesh_flecha_pase.mesh = imm
	_mesh_flecha_pase.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_indicador_cono_pase.add_child(_mesh_flecha_pase)

	add_child(_indicador_cono_pase)
	_indicador_cono_pase.visible = false


func _inicializar_jugadores_entrenamiento() -> void:
	if contenedor_jugadores == null:
		return

	_asegurar_companeros_equipo()

	for n: Node in contenedor_jugadores.get_children():
		var j: Jugador3D = n as Jugador3D
		if j == null:
			continue
		var eq_id: int = 1 if j.name.begins_with("Vis_") else 0
		j.aplicar_uniforme_equipo(eq_id)
		j.finalizar_entrada_cancha()
		j.es_controlado = (j == lanzador)
	
	_defensores_barrera.clear()
	_defensores_barrera.append(def_barrera_1)
	_defensores_barrera.append(def_barrera_2)
	_defensores_barrera.append(def_barrera_3)
	
	if portero_rival:
		portero_rival.posicion_tactica = "PORTERO"
		portero_rival.es_arquero = true
		portero_rival._configurar_hitboxes_anatomicas_portero()
		if not portero_rival.atajada_realizada.is_connected(_on_atajada_realizada):
			portero_rival.atajada_realizada.connect(_on_atajada_realizada)


## Instancia y configura dinámicamente a los dos compañeros de equipo (Companero_Banda y Companero_Frontal)
## con uniforme rojo (Local) para ofrecer líneas de pase viables durante el tiro libre.
func _asegurar_companeros_equipo() -> void:
	if contenedor_jugadores == null:
		return

	companero_banda = contenedor_jugadores.get_node_or_null("Companero_Banda") as Jugador3D
	if companero_banda == null:
		companero_banda = ESCENA_JUGADOR_3D.instantiate() as Jugador3D
		companero_banda.name = "Companero_Banda"
		companero_banda.posicion_tactica = "ALA_DER"
		companero_banda.dorsal = 7
		companero_banda.nombre_jugador = "C. Banda"
		contenedor_jugadores.add_child(companero_banda)

	companero_frontal = contenedor_jugadores.get_node_or_null("Companero_Frontal") as Jugador3D
	if companero_frontal == null:
		companero_frontal = ESCENA_JUGADOR_3D.instantiate() as Jugador3D
		companero_frontal.name = "Companero_Frontal"
		companero_frontal.posicion_tactica = "ALA_IZQ"
		companero_frontal.dorsal = 8
		companero_frontal.nombre_jugador = "F. Frontal"
		contenedor_jugadores.add_child(companero_frontal)

	for comp: Jugador3D in [companero_banda, companero_frontal]:
		if comp != null:
			comp.aplicar_uniforme_equipo(0)
			comp.finalizar_entrada_cancha()
			comp.es_controlado = false
			comp.set_congelado(true)


func _conectar_senales_ui() -> void:
	if btn_confirmar:
		btn_confirmar.pressed.connect(_on_confirmar_posicion_pressed)
	if btn_cambiar_vista:
		btn_cambiar_vista.pressed.connect(_on_cambiar_vista_pressed)
	if btn_elegir_lanzador:
		btn_elegir_lanzador.pressed.connect(_on_elegir_lanzador_pressed)
	if btn_cambio_posicion:
		btn_cambio_posicion.pressed.connect(_on_cambio_posicion_pressed)
	if btn_salir_menu:
		btn_salir_menu.pressed.connect(_on_salir_menu_pressed)
	if btn_modo_regla:
		btn_modo_regla.pressed.connect(_on_modo_regla_pressed)
	if touch_controls:
		if not touch_controls.pase_solicitado.is_connected(_on_touch_pase_solicitado):
			touch_controls.pase_solicitado.connect(_on_touch_pase_solicitado)
		if not touch_controls.hueco_solicitado.is_connected(_on_touch_hueco_solicitado):
			touch_controls.hueco_solicitado.connect(_on_touch_hueco_solicitado)
		if not touch_controls.tiro_solicitado.is_connected(_on_touch_tiro_solicitado):
			touch_controls.tiro_solicitado.connect(_on_touch_tiro_solicitado)


func _on_modo_regla_pressed() -> void:
	if _en_secuencia_carrera_tl or estado_actual == EstadoEntrenamiento.TRANSICION_FADE:
		return
	_indice_modo_regla = (_indice_modo_regla + 1) % 3
	if _indice_modo_regla == 0:
		es_tiro_indirecto = false
		faltas_acumuladas = 1
	elif _indice_modo_regla == 1:
		es_tiro_indirecto = true
		faltas_acumuladas = 1
	else:
		es_tiro_indirecto = false
		faltas_acumuladas = 6
	_actualizar_boton_modo_regla()
	_actualizar_indicador_visual_balon()
	if estado_actual == EstadoEntrenamiento.EJECUCION and not _disparo_realizado:
		_iniciar_estado_ejecucion()


func _actualizar_boton_modo_regla() -> void:
	if btn_modo_regla == null:
		return
	if faltas_acumuladas >= 6:
		btn_modo_regla.text = "⚖ MODO: 6ª FALTA (SIN BARRERA)"
	elif es_tiro_indirecto:
		btn_modo_regla.text = "⚖ MODO: TIRO INDIRECTO (2 TOQUES)"
	else:
		btn_modo_regla.text = "⚖ MODO: TIRO DIRECTO"


func _obtener_radio_balon_efectivo() -> float:
	if balon != null and is_instance_valid(balon) and balon.has_method("obtener_radio_efectivo"):
		return balon.obtener_radio_efectivo()
	return radio_balon


# ==============================================================================
# 1. ESTADO: SELECCIÓN INTERACTIVA DE POSICIÓN DE FALTA (VISTA CENITAL)
# ==============================================================================

func _entrar_estado_seleccion_posicion(inmediato: bool = false) -> void:
	estado_actual = EstadoEntrenamiento.SELECCION_POSICION
	if timer_saque_4s:
		timer_saque_4s.stop()
	cuenta_regresiva_4s_actualizada.emit(0.0, false)
	toques_en_jugada = 0
	_disparo_realizado = false
	_en_secuencia_carrera_tl = false
	_tiempo_carrera_tl = 0.0
	_tiempo_post_impacto = 0.0
	_ultimo_mensaje_atajada = ""
	_jugador_activo_actual = lanzador
	_en_jugada_de_pase = false
	_receptor_pase = null
	_pase_en_transito = false
	_tiempo_espera_pase = 0.0
	_pan_touch_id = -1
	_capturando_swipe = false
	_arrastrando_balon = false
	_swipe_puntos.clear()
	if _indicador_cono_pase:
		_indicador_cono_pase.visible = false
	if touch_controls:
		touch_controls.visible = false
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = false
	if panel_cuenta_4s:
		panel_cuenta_4s.visible = false
	if capa_trazo_swipe:
		capa_trazo_swipe.queue_redraw()

	if panel_seleccion:
		panel_seleccion.visible = true
	if panel_ejecucion:
		panel_ejecucion.visible = false
	if banner_resultado:
		banner_resultado.visible = false

	# Restablecer física del balón y sincronizarlo en el plano horizontal (Y = radio_balon) junto al indicador circular verde
	var hit_pos_inicial: Vector3 = Vector3(_pos_falta_seleccionada.x, 0.0, _pos_falta_seleccionada.z)
	_pos_falta_seleccionada = hit_pos_inicial
	_pos_ejecucion_efectiva = hit_pos_inicial
	var r_balon: float = _obtener_radio_balon_efectivo()
	var pos_balon_inicial: Vector3 = Vector3(hit_pos_inicial.x, r_balon, hit_pos_inicial.z)
	if balon:
		balon.configurar_saque_reglamentario(pos_balon_inicial, lanzador, es_tiro_indirecto)
		balon.sacador_autorizado = null
		balon.linear_velocity = Vector3.ZERO
		balon.angular_velocity = Vector3.ZERO
		balon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		balon.freeze = true
		balon.global_position = pos_balon_inicial
	if indicador_circulo_verde:
		indicador_circulo_verde.global_position = Vector3(hit_pos_inicial.x, 0.02, hit_pos_inicial.z)

	_actualizar_indicador_visual_balon()

	# Apartar temporalmente al lanzador en espera mientras se elige el punto en vista cenital (NO se arrastra)
	if lanzador:
		lanzador.soltar_posesion()
		lanzador.fijar_en_saque(true, Vector3(-2.0, 0.0, 0.0))
		lanzador.look_at(Vector3(hit_pos_inicial.x, 0.0, hit_pos_inicial.z), Vector3.UP)
		lanzador.rotation.x = 0.0
		lanzador.rotation.z = 0.0
		lanzador.set_congelado(true)

	# Apartar a los compañeros de equipo sobre la banda en vista cenital
	if companero_banda:
		companero_banda.soltar_posesion()
		companero_banda.es_controlado = false
		companero_banda.fijar_en_saque(true, Vector3(2.5, 0.0, 7.8))
		companero_banda.look_at(Vector3(hit_pos_inicial.x, 0.0, hit_pos_inicial.z), Vector3.UP)
		companero_banda.rotation.x = 0.0
		companero_banda.rotation.z = 0.0
		companero_banda.set_congelado(true)

	if companero_frontal:
		companero_frontal.soltar_posesion()
		companero_frontal.es_controlado = false
		companero_frontal.fijar_en_saque(true, Vector3(6.5, 0.0, -7.8))
		companero_frontal.look_at(Vector3(hit_pos_inicial.x, 0.0, hit_pos_inicial.z), Vector3.UP)
		companero_frontal.rotation.x = 0.0
		companero_frontal.rotation.z = 0.0
		companero_frontal.set_congelado(true)

	for i: int in range(_defensores_barrera.size()):
		var def: Jugador3D = _defensores_barrera[i]
		if def:
			def.establecer_pose_barrera(false)
			def.fijar_en_saque(true, Vector3(17.5, 0.0, -5.5 + float(i) * 5.5))
			def.set_congelado(true)

	if portero_rival:
		portero_rival.soltar_posesion()
		portero_rival.fijar_en_saque(false)
		portero_rival.global_position = Vector3(19.35, 0.0, 0.0)
		portero_rival.velocity = Vector3.ZERO
		portero_rival.set_congelado(true)

	# Colocar cámara en vista cenital enfocando el medio campo rival
	if camara:
		camara.activar_camara_cenital_seleccion(Vector3(10.2, 0.0, 0.0), 23.5, inmediato)


func _actualizar_indicador_visual_balon() -> void:
	if indicador_circulo_verde:
		indicador_circulo_verde.visible = (estado_actual == EstadoEntrenamiento.SELECCION_POSICION)
		indicador_circulo_verde.global_position = Vector3(_pos_falta_seleccionada.x, 0.02, _pos_falta_seleccionada.z)
	
	if label_coord_seleccion:
		var dist_arco: float = Vector2(_pos_falta_seleccionada.x, _pos_falta_seleccionada.z).distance_to(Vector2(20.0, 0.0))
		if faltas_acumuladas >= 6:
			var texto_punto: String = "2° PENAL 10.0m" if dist_arco > 10.0 else "PUNTO FALTA %.1fm" % dist_arco
			label_coord_seleccion.text = "6ª FALTA ACUMULADA (SIN BARRERA)  •  EJECUCIÓN: %s" % texto_punto
		else:
			var num_barrera: int = 3 if dist_arco < 12.0 else 2
			var texto_tipo: String = "INDIRECTO" if es_tiro_indirecto else "DIRECTO"
			label_coord_seleccion.text = "TIRO %s  •  DISTANCIA: %.1f m  (BARRERA A 5M: %d)" % [texto_tipo, dist_arco, num_barrera]


## Proyecta un rayo desde la cámara cenital contra el plano del suelo Plane(Vector3.UP, 0.0),
## restringe el impacto dentro de los límites reglamentarios del medio campo ofensivo y asigna
## la posición EXCLUSIVAMENTE al balón y al aro verde indicador. El jugador NO se arrastra.
func _mover_balon_segun_pantalla(pos_pantalla: Vector2) -> void:
	if camara == null or balon == null:
		return
	
	var ray_origin: Vector3 = camara.project_ray_origin(pos_pantalla)
	var ray_dir: Vector3 = camara.project_ray_normal(pos_pantalla)
	var hit_variant: Variant = Plane(Vector3.UP, 0.0).intersects_ray(ray_origin, ray_dir)
	if hit_variant == null:
		return
	
	var punto_pista: Vector3 = hit_variant as Vector3
	
	# Clamping reglamentario dentro del medio campo ofensivo y fuera del área de meta rival (6m)
	var x_clamp: float = clampf(punto_pista.x, min_x_seleccion, max_x_seleccion)
	var z_clamp: float = clampf(punto_pista.z, -max_z_seleccion, max_z_seleccion)
	
	# Evitar que el tiro libre se sitúe dentro del área penal rival (X > 14.0 y |Z| < 3.2)
	var pos_arco: Vector2 = Vector2(20.0, 0.0)
	var pos_cand_2d: Vector2 = Vector2(x_clamp, z_clamp)
	if pos_cand_2d.distance_to(pos_arco) < 6.2:
		var dir_afuera: Vector2 = (pos_cand_2d - pos_arco).normalized()
		if dir_afuera.length_squared() < 0.001:
			dir_afuera = Vector2(-1.0, 0.0)
		pos_cand_2d = pos_arco + dir_afuera * 6.2
		x_clamp = clampf(pos_cand_2d.x, min_x_seleccion, max_x_seleccion)
		z_clamp = clampf(pos_cand_2d.y, -max_z_seleccion, max_z_seleccion)
	
	var hit_pos: Vector3 = Vector3(x_clamp, 0.0, z_clamp)
	_pos_falta_seleccionada = hit_pos
	
	# El objeto arrastrado DEBE ser el Balón, NO el Jugador
	var alt_balon: float = _obtener_radio_balon_efectivo()
	balon.global_position = Vector3(hit_pos.x, alt_balon, hit_pos.z)
	if indicador_circulo_verde:
		indicador_circulo_verde.global_position = Vector3(hit_pos.x, 0.02, hit_pos.z)
	
	_actualizar_indicador_visual_balon()


func _on_confirmar_posicion_pressed() -> void:
	if estado_actual != EstadoEntrenamiento.SELECCION_POSICION:
		return
	_iniciar_estado_ejecucion()


# ==============================================================================
# 2. ESTADO: EJECUCIÓN DEL TIRO LIBRE (PERSPECTIVA TRASERA + REGLAS FIFA/IFAB)
# ==============================================================================

func _iniciar_estado_ejecucion() -> void:
	estado_actual = EstadoEntrenamiento.EJECUCION
	_disparo_realizado = false
	_en_secuencia_carrera_tl = false
	_tiempo_carrera_tl = 0.0
	_tiempo_post_impacto = 0.0
	_ultimo_mensaje_atajada = ""
	_vista_cenital_alterna = false
	_pan_touch_id = -1
	_capturando_swipe = false
	_swipe_puntos.clear()
	toques_en_jugada = 0
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = false
	if capa_trazo_swipe:
		capa_trazo_swipe.queue_redraw()

	if indicador_circulo_verde:
		indicador_circulo_verde.visible = false
	if panel_seleccion:
		panel_seleccion.visible = false
	if panel_ejecucion:
		panel_ejecucion.visible = true
	if label_guia_swipe:
		label_guia_swipe.visible = true

	var pos_arco_rival: Vector3 = Vector3(20.0, 0.0, 0.0)
	var pos_falta_plana: Vector3 = Vector3(_pos_falta_seleccionada.x, 0.0, _pos_falta_seleccionada.z)
	
	# En modo entrenamiento libre, respetar exactamente las coordenadas elegidas por el usuario
	if faltas_acumuladas >= 6 and not es_entrenamiento_activo():
		es_tiro_indirecto = false
		if pos_falta_plana.distance_to(pos_arco_rival) > 10.0:
			_pos_ejecucion_efectiva = Vector3(10.0, 0.0, 0.0)
		else:
			_pos_ejecucion_efectiva = pos_falta_plana
	else:
		_pos_ejecucion_efectiva = pos_falta_plana

	# 1. Sincronización inmediata de posición del Balón:
	# Actualiza instantáneamente el transform en SceneTree y PhysicsServer3D antes del primer frame
	var r_balon: float = _obtener_radio_balon_efectivo()
	var pos_balon_ejecucion: Vector3 = Vector3(_pos_ejecucion_efectiva.x, r_balon, _pos_ejecucion_efectiva.z)
	if balon:
		if balon.has_method("soltar_posesion"):
			balon.soltar_posesion()
		balon.sacador_autorizado = null
		balon.linear_velocity = Vector3.ZERO
		balon.angular_velocity = Vector3.ZERO
		balon.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		balon.freeze = true
		balon.sleeping = true
		balon.global_position = pos_balon_ejecucion
		balon.global_transform.origin = pos_balon_ejecucion
		PhysicsServer3D.body_set_state(balon.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), pos_balon_ejecucion))
		PhysicsServer3D.body_set_state(balon.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(balon.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
		balon.configurar_saque_reglamentario(pos_balon_ejecucion, lanzador, es_tiro_indirecto)
		balon.freeze = true

	# 2. Dirección hacia el centro del arco rival
	var dir_arco: Vector3 = (pos_arco_rival - pos_balon_ejecucion).normalized()
	dir_arco.y = 0.0
	dir_arco = dir_arco.normalized()
	_base_forward_tl = dir_arco
	_direccion_apuntado_tactico = dir_arco

	# 3. Situar al lanzador en el offset relativo correcto respecto al balón (1.5 m detrás mirando al arco)
	# NUNCA directamente encima de las coordenadas del balón o reemplazándolo
	var pos_lanzador: Vector3 = pos_balon_ejecucion - dir_arco * 1.5
	pos_lanzador.y = 0.0
	_pos_fija_lanzador = pos_lanzador

	var pateador: Jugador3D = lanzador
	_jugador_activo_actual = pateador
	if pateador:
		pateador.es_controlado = true
		pateador.soltar_posesion()
		pateador.set_congelado(false)
		pateador.global_position = pos_lanzador
		pateador.look_at(pos_balon_ejecucion + dir_arco * 5.0, Vector3.UP)
		pateador.rotation.x = 0.0
		pateador.rotation.z = 0.0
		pateador.velocity = Vector3.ZERO
		pateador.fijar_en_saque(true, pos_lanzador)

	# 4. Posicionar la formación defensiva según el modo reglamentario (Barrera a 5.0m o 6ª falta sin barrera)
	_posicionar_barrera_rival_5m(pos_balon_ejecucion, pos_arco_rival, dir_arco)

	# 5. Posicionar a los compañeros de equipo en líneas de pase viables fuera de la barrera (Uniforme Rojo)
	_posicionar_companeros_tiro_libre(pos_balon_ejecucion, pos_arco_rival, dir_arco)

	# 6. Conmutación inteligente de vista y controles según distancia a portería (Estilo eFootball):
	# - Si la infracción ocurre detrás de umbral_distancia_remate (> 15.0m): vista por defecto táctica/cenital,
	#   desactivando el lienzo de trazo y mostrando el joystick virtual con botones de acción ("Pase", "Pase Filtrado", "Disparo").
	# - Si la falta está dentro del rango de remate (<= 15.0m): vista por defecto trasera OTS con interfaz táctil de trazo curvo.
	var dist_arco_ejecucion: float = pos_balon_ejecucion.distance_to(pos_arco_rival)
	var es_tiro_lejano: bool = dist_arco_ejecucion > umbral_distancia_remate
	_aplicar_modo_vista_tactica_o_tiro(es_tiro_lejano, true)

	# 7. Desactivación del temporizador reglamentario en Entrenamiento:
	# En modo entrenamiento libre, se desactiva por completo el temporizador de 4 s y aviso de "Tiempo agotado".
	# El lanzador puede permanecer en la fase de preparación de tiro de forma indefinida.
	_reproducir_pitido_arbitral()
	if timer_saque_4s:
		timer_saque_4s.stop()
	if es_entrenamiento_activo():
		_actualizar_hud_cuenta_4s(0.0, false)
	else:
		if timer_saque_4s:
			timer_saque_4s.wait_time = tiempo_saque
			timer_saque_4s.start(tiempo_saque)
		_actualizar_hud_cuenta_4s(tiempo_saque, true)


## Posiciona la formación defensiva aplicando las Reglas Oficiales de Futsal (FIFA/IFAB):
## - En Tiro Libre con barrera (`faltas_acumuladas < 6`):
##   `pos_barrera = balon.global_position + (arco_rival.global_position - balon.global_position).normalized() * 5.0`
##   Ningún jugador rival puede estar dentro de un radio inferior a 5.0 metros del balón.
## - En 6ª Falta Acumulada (`faltas_acumuladas >= 6`):
##   Se desactiva por completo la barrera; todos los jugadores de campo se sitúan detrás de la línea paralela al balón
##   y a >= 5.0m; el portero rival puede adelantarse hasta un límite de 5.0m respecto al balón.
func _posicionar_barrera_rival_5m(pos_balon: Vector3, pos_arco: Vector3, _dir_arco: Vector3) -> void:
	_posiciones_barrera.clear()
	var pos_balon_plana: Vector3 = Vector3(pos_balon.x, 0.0, pos_balon.z)
	var dir_arco_unit: Vector3 = (pos_arco - pos_balon_plana).normalized()
	if dir_arco_unit.length_squared() < 0.01:
		dir_arco_unit = Vector3(1.0, 0.0, 0.0)

	# Caso 6ª Falta Acumulada: Tiro Libre Directo sin Barrera
	if faltas_acumuladas >= 6:
		var x_detras_balon: float = clampf(pos_balon_plana.x - (distancia_barrera + 0.5), -18.0, pos_balon_plana.x - 5.1)
		for i: int in range(_defensores_barrera.size()):
			var def_dp: Jugador3D = _defensores_barrera[i]
			if def_dp == null:
				continue
			var z_fila: float = -6.0 + float(i) * 6.0
			if Vector2(x_detras_balon, z_fila).distance_to(Vector2(pos_balon_plana.x, pos_balon_plana.z)) < distancia_barrera:
				z_fila = -7.8 if pos_balon_plana.z >= 0.0 else 7.8
			var pos_despejada: Vector3 = Vector3(x_detras_balon, 0.0, z_fila)
			def_dp.set_congelado(false)
			def_dp.establecer_pose_barrera(false)
			def_dp.fijar_en_saque(true, pos_despejada)
			def_dp.rotation.y = atan2(-dir_arco_unit.x, -dir_arco_unit.z)
			def_dp.velocity = Vector3.ZERO
			_posiciones_barrera.append(pos_despejada)

		# El portero rival puede adelantarse hasta un límite de 5.0 metros respecto al balón
		if portero_rival:
			var pos_gk_5m: Vector3 = pos_balon_plana + dir_arco_unit * distancia_barrera
			pos_gk_5m.x = clampf(pos_gk_5m.x, 14.0, 19.35)
			pos_gk_5m.z = clampf(pos_gk_5m.z, -1.65, 1.65)
			portero_rival.soltar_posesion()
			portero_rival.fijar_en_saque(false)
			portero_rival.global_position = Vector3(pos_gk_5m.x, 0.0, pos_gk_5m.z)
			portero_rival.velocity = Vector3.ZERO
			var dir_mira_gk_dp: Vector3 = (pos_balon_plana - portero_rival.global_position).normalized()
			portero_rival.rotation.y = atan2(-dir_mira_gk_dp.x, -dir_mira_gk_dp.z)
			portero_rival.set_congelado(false)
		return

	# Caso estándar (1ª a 5ª falta): Barrera reglamentaria a exactamente 5.0m hacia el centro del arco rival
	var dist_al_arco: float = pos_balon_plana.distance_to(pos_arco)
	var num_barrera: int = 3 if dist_al_arco < 12.0 else 2

	var signo_poste_cercano: float = -1.0
	if pos_balon.z > 0.15:
		signo_poste_cercano = 1.0
	elif pos_balon.z < -0.15:
		signo_poste_cercano = -1.0

	var pos_barrera: Vector3 = pos_balon_plana + dir_arco_unit * distancia_barrera
	var vec_perp: Vector3 = Vector3(-dir_arco_unit.z, 0.0, dir_arco_unit.x).normalized()

	# Separación hombro con hombro reglamentaria de 0.55 m entre cada defensor de la barrera
	var offsets: Array[float] = []
	if num_barrera == 2:
		offsets = [-0.275, 0.275]
	else:
		offsets = [-0.55, 0.0, 0.55]

	for i: int in range(_defensores_barrera.size()):
		var def: Jugador3D = _defensores_barrera[i]
		if def == null:
			continue
		if i < num_barrera:
			var pos_5m: Vector3 = pos_barrera + vec_perp * offsets[i]
			pos_5m.x = clampf(pos_5m.x, -18.8, 18.8)
			pos_5m.z = clampf(pos_5m.z, -9.2, 9.2)
			pos_5m.y = 0.0
			def.set_congelado(false)
			def.fijar_en_saque(true, pos_5m)
			def.establecer_pose_barrera(true)
			var dir_mira: Vector3 = (pos_balon_plana - pos_5m).normalized()
			def.rotation.y = atan2(-dir_mira.x, -dir_mira.z)
			def.velocity = Vector3.ZERO
			_posiciones_barrera.append(pos_5m)
		else:
			# Ningún jugador rival puede estar dentro de un radio inferior a 5.0 metros del balón
			var pos_fuera: Vector3 = Vector3(clampf(pos_barrera.x + 1.5, 6.0, 18.0), 0.0, -7.2 if pos_balon.z >= 0.0 else 7.2)
			if pos_fuera.distance_to(pos_balon_plana) < distancia_barrera:
				pos_fuera = pos_balon_plana + (pos_fuera - pos_balon_plana).normalized() * (distancia_barrera + 0.5)
			def.set_congelado(false)
			def.fijar_en_saque(true, pos_fuera)
			def.establecer_pose_barrera(false)
			def.velocity = Vector3.ZERO
			_posiciones_barrera.append(pos_fuera)

	# El arquero rival cubre el poste opuesto con visión limpia hacia el lanzador
	if portero_rival:
		var z_poste_opuesto: float = -signo_poste_cercano * clampf(0.68 + absf(pos_balon.z) * 0.05, 0.62, 1.12)
		portero_rival.soltar_posesion()
		portero_rival.fijar_en_saque(false)
		portero_rival.global_position = Vector3(19.35, 0.0, z_poste_opuesto)
		portero_rival.velocity = Vector3.ZERO
		var dir_mira_gk: Vector3 = (pos_balon_plana - portero_rival.global_position).normalized()
		portero_rival.rotation.y = atan2(-dir_mira_gk.x, -dir_mira_gk.z)
		portero_rival.set_congelado(false)


## Posiciona a los dos compañeros de equipo (Companero_Banda y Companero_Frontal) en líneas de pase viables,
## garantizando que estén fuera del radio de 5.0m de la barrera rival, anclados a Y = 0.0 y mirando al balón.
func _posicionar_companeros_tiro_libre(pos_balon: Vector3, _pos_arco: Vector3, _dir_arco: Vector3) -> void:
	if companero_banda == null or companero_frontal == null:
		_asegurar_companeros_equipo()

	var pos_b_plana: Vector3 = Vector3(pos_balon.x, 0.0, pos_balon.z)

	# 1. Companero_Banda: Ubicado sobre la banda derecha / abierta, adelantado respecto al balón (X + 4.0m)
	var offset_z_banda: float = -3.2 if pos_b_plana.z >= 0.0 else 3.2
	var pos_sug_banda: Vector3 = pos_b_plana + Vector3(4.0, 0.0, offset_z_banda)
	var pos_final_banda: Vector3 = _ajustar_posicion_companero(pos_sug_banda, pos_b_plana)

	if companero_banda and is_instance_valid(companero_banda):
		companero_banda.soltar_posesion()
		companero_banda.es_controlado = false
		companero_banda.set_congelado(false)
		companero_banda.global_position = pos_final_banda
		companero_banda.global_position.y = 0.0
		companero_banda.look_at(pos_balon, Vector3.UP)
		companero_banda.rotation.x = 0.0
		companero_banda.rotation.z = 0.0
		companero_banda.fijar_en_saque(false)
		companero_banda.velocity = Vector3.ZERO
		companero_banda.es_opcion_de_pase = true
		if companero_banda.indicador_control:
			companero_banda.indicador_control.visible = true

	# 2. Companero_Frontal: Ubicado en la frontal del área rival o segundo palo para remate de primera
	var offset_z_frontal: float = -4.5 if pos_b_plana.z >= 0.0 else 4.5
	var x_frontal: float = clampf(pos_b_plana.x + 2.5, 11.5, 14.5)
	var pos_sug_frontal: Vector3 = Vector3(x_frontal, 0.0, pos_b_plana.z + offset_z_frontal)
	var pos_final_frontal: Vector3 = _ajustar_posicion_companero(pos_sug_frontal, pos_b_plana)

	if companero_frontal and is_instance_valid(companero_frontal):
		companero_frontal.soltar_posesion()
		companero_frontal.es_controlado = false
		companero_frontal.set_congelado(false)
		companero_frontal.global_position = pos_final_frontal
		companero_frontal.global_position.y = 0.0
		companero_frontal.look_at(pos_balon, Vector3.UP)
		companero_frontal.rotation.x = 0.0
		companero_frontal.rotation.z = 0.0
		companero_frontal.fijar_en_saque(false)
		companero_frontal.velocity = Vector3.ZERO
		companero_frontal.es_opcion_de_pase = true
		if companero_frontal.indicador_control:
			companero_frontal.indicador_control.visible = true


## Ajusta la posición de un compañero para asegurar que permanezca dentro de los límites de pista,
## anclado exactamente en Y = 0.0, a >= 5.0m de la barrera rival y sin colisionar con defensores ni arquero.
func _ajustar_posicion_companero(pos_sugerida: Vector3, pos_balon: Vector3) -> Vector3:
	var pos_aj: Vector3 = pos_sugerida
	pos_aj.x = clampf(pos_aj.x, 2.0, 18.0)
	pos_aj.z = clampf(pos_aj.z, -8.6, 8.6)
	pos_aj.y = 0.0

	# 1. Evitar interferencia y respetar radio mínimo de 5.0m con la barrera rival y sus defensores
	for pos_def: Vector3 in _posiciones_barrera:
		var dist_def: float = pos_aj.distance_to(pos_def)
		if dist_def < 2.5:
			var dir_sep: Vector3 = (pos_aj - pos_def).normalized()
			if dir_sep.length_squared() < 0.01:
				dir_sep = Vector3(0.0, 0.0, 1.0)
			dir_sep.y = 0.0
			pos_aj = pos_def + dir_sep.normalized() * 2.6
			pos_aj.x = clampf(pos_aj.x, 2.0, 18.0)
			pos_aj.z = clampf(pos_aj.z, -8.6, 8.6)
			pos_aj.y = 0.0

	# 2. Respetar distancia mínima de aproximación con el balón (>= 2.2m)
	if pos_aj.distance_to(pos_balon) < 2.2:
		var dir_balon: Vector3 = (pos_aj - pos_balon).normalized()
		if dir_balon.length_squared() < 0.01:
			dir_balon = Vector3(1.0, 0.0, 0.0)
		dir_balon.y = 0.0
		pos_aj = pos_balon + dir_balon.normalized() * 2.5
		pos_aj.x = clampf(pos_aj.x, 2.0, 18.0)
		pos_aj.z = clampf(pos_aj.z, -8.6, 8.6)
		pos_aj.y = 0.0

	# 3. No obstruir el área chica del arquero rival (X > 18.5)
	if pos_aj.x > 18.2:
		pos_aj.x = 18.0

	pos_aj.y = 0.0
	return pos_aj


# ==============================================================================
# 3. GESTIÓN DE INPUT TÁCTIL (DRAG EN SELECCIÓN Y PANTALLA DIVIDIDA EN EJECUCIÓN)
# ==============================================================================

func _input(event: InputEvent) -> void:
	if estado_actual == EstadoEntrenamiento.TRANSICION_FADE:
		return

	if estado_actual == EstadoEntrenamiento.SELECCION_POSICION:
		_manejar_input_seleccion_posicion(event)
	elif estado_actual == EstadoEntrenamiento.EJECUCION and not _disparo_realizado and not _en_secuencia_carrera_tl:
		if _vista_cenital_alterna:
			_manejar_input_tactico(event)
		else:
			_manejar_input_swipe_ejecucion(event)


func _es_clic_sobre_ui_interactiva(pos_pantalla: Vector2) -> bool:
	var botones_activos: Array[Button] = [
		btn_confirmar,
		btn_cambiar_vista,
		btn_elegir_lanzador,
		btn_cambio_posicion,
		btn_salir_menu,
		btn_modo_regla
	]
	for b: Button in botones_activos:
		if b != null and b.is_visible_in_tree() and b.get_global_rect().has_point(pos_pantalla):
			return true
	if touch_controls != null and touch_controls.is_visible_in_tree():
		if touch_controls.joystick_base != null and touch_controls.joystick_base.get_global_rect().grow(25.0).has_point(pos_pantalla):
			return true
		if touch_controls.botones_accion != null and touch_controls.botones_accion.get_global_rect().grow(15.0).has_point(pos_pantalla):
			return true
	return false


func _obtener_pos_event(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.position
	elif event is InputEventMouseButton or event is InputEventMouseMotion:
		return event.position
	return Vector2.ZERO


func _manejar_input_tactico(event: InputEvent) -> void:
	if _es_clic_sobre_ui_interactiva(_obtener_pos_event(event)):
		return
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			_procesar_toque_tactil_pase(touch.position)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_procesar_toque_tactil_pase(mb.position)


func _manejar_input_seleccion_posicion(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _es_clic_sobre_ui_interactiva(touch.position):
				return
			_arrastrando_balon = true
			_drag_touch_id = touch.index
			_mover_balon_segun_pantalla(touch.position)
		else:
			if touch.index == _drag_touch_id:
				_arrastrando_balon = false
				_drag_touch_id = -1

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if _arrastrando_balon and drag.index == _drag_touch_id:
			_mover_balon_segun_pantalla(drag.position)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _es_clic_sobre_ui_interactiva(mb.position):
					return
				_arrastrando_balon = true
				_drag_touch_id = -99
				_mover_balon_segun_pantalla(mb.position)
			else:
				if _drag_touch_id == -99:
					_arrastrando_balon = false
					_drag_touch_id = -1

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _arrastrando_balon and _drag_touch_id == -99:
			_mover_balon_segun_pantalla(mm.position)


func _manejar_input_swipe_ejecucion(event: InputEvent) -> void:
	var view_w: float = get_viewport().get_visible_rect().size.x
	var limite_x_paneo: float = view_w * 0.45

	if event is InputEventScreenTouch:
		var touch: InputEventScreenTouch = event
		if touch.pressed:
			if _es_clic_sobre_ui_interactiva(touch.position):
				return
			if touch.position.x < limite_x_paneo:
				_iniciar_paneo_camara(touch.index, touch.position)
			else:
				_iniciar_trazo_swipe(touch.index, touch.position)
		else:
			if touch.index == _pan_touch_id:
				_finalizar_paneo_camara(touch.position)
			elif touch.index == _swipe_touch_id:
				_finalizar_trazo_swipe(touch.position)

	elif event is InputEventScreenDrag:
		var drag: InputEventScreenDrag = event
		if drag.index == _pan_touch_id:
			_actualizar_paneo_camara(drag.position)
		elif _capturando_swipe and drag.index == _swipe_touch_id:
			_actualizar_trazo_swipe(drag.position)

	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if _es_clic_sobre_ui_interactiva(mb.position):
					return
				if mb.position.x < limite_x_paneo:
					_iniciar_paneo_camara(-98, mb.position)
				else:
					_iniciar_trazo_swipe(-99, mb.position)
			else:
				if _pan_touch_id == -98:
					_finalizar_paneo_camara(mb.position)
				if _swipe_touch_id == -99:
					_finalizar_trazo_swipe(mb.position)

	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if _pan_touch_id == -98:
			_actualizar_paneo_camara(mm.position)
		elif _capturando_swipe and _swipe_touch_id == -99:
			_actualizar_trazo_swipe(mm.position)


func _iniciar_paneo_camara(touch_id: int, pos: Vector2) -> void:
	_pan_touch_id = touch_id
	_pan_pos_previa = pos
	_pan_pos_inicio = pos
	_pan_tiempo_inicio = Time.get_ticks_msec() / 1000.0


func _actualizar_paneo_camara(pos: Vector2) -> void:
	if _disparo_realizado or _en_secuencia_carrera_tl or _en_jugada_de_pase:
		return
	var delta_x: float = pos.x - _pan_pos_previa.x
	_pan_pos_previa = pos
	if camara != null:
		camara.ajustar_paneo_tiro_libre(-delta_x * 0.0022)
		var dir_apuntado: Vector3 = camara.obtener_direccion_apuntado_tl()
		dir_apuntado.y = 0.0
		if dir_apuntado.length_squared() > 0.01:
			dir_apuntado = dir_apuntado.normalized()
		var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
		if pateador != null and is_instance_valid(pateador) and balon != null:
			var pos_lanzador: Vector3 = balon.global_position - dir_apuntado * 1.5
			pos_lanzador.y = 0.0
			pateador.global_position = pos_lanzador
			pateador.look_at(balon.global_position + dir_apuntado * 5.0, Vector3.UP)
			pateador.rotation.x = 0.0
			pateador.rotation.z = 0.0
			pateador.fijar_en_saque(true, pos_lanzador)


func _finalizar_paneo_camara(pos: Vector2 = Vector2.ZERO) -> void:
	if _pan_touch_id != -1 and pos != Vector2.ZERO:
		var duracion: float = (Time.get_ticks_msec() / 1000.0) - _pan_tiempo_inicio
		var dist_recorrida: float = pos.distance_to(_pan_pos_inicio)
		if dist_recorrida < 25.0 and duracion < 0.40:
			if _procesar_toque_tactil_pase(pos):
				_pan_touch_id = -1
				return
	_pan_touch_id = -1


func _iniciar_trazo_swipe(touch_id: int, pos: Vector2) -> void:
	_swipe_touch_id = touch_id
	_capturando_swipe = true
	_swipe_puntos.clear()
	_swipe_puntos.append(pos)
	_swipe_tiempo_inicio = Time.get_ticks_msec() / 1000.0
	_potencia_swipe_actual = 0.15
	_comba_swipe_actual = 0.0
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = true
		barra_potencia_swipe.value = _potencia_swipe_actual
	if capa_trazo_swipe:
		capa_trazo_swipe.queue_redraw()


func _actualizar_trazo_swipe(pos: Vector2) -> void:
	if not _capturando_swipe:
		return
	if _swipe_puntos.is_empty() or pos.distance_to(_swipe_puntos[-1]) >= 4.0:
		_swipe_puntos.append(pos)
		_recalcular_metricas_swipe_en_vivo()
		if capa_trazo_swipe:
			capa_trazo_swipe.queue_redraw()


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
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = true
		barra_potencia_swipe.value = _potencia_swipe_actual

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


func _finalizar_trazo_swipe(pos_final: Vector2 = Vector2.ZERO) -> void:
	if not _capturando_swipe:
		return
	_capturando_swipe = false
	_swipe_touch_id = -1

	if _swipe_puntos.is_empty():
		return

	if _swipe_puntos.size() < 2:
		var p_tap: Vector2 = _swipe_puntos[0]
		_swipe_puntos.clear()
		if barra_potencia_swipe:
			barra_potencia_swipe.visible = false
		if capa_trazo_swipe:
			capa_trazo_swipe.queue_redraw()
		_procesar_toque_tactil_pase(p_tap)
		return

	var p0: Vector2 = _swipe_puntos[0]
	var p1: Vector2 = _swipe_puntos[-1]
	var delta_vec: Vector2 = p1 - p0
	if delta_vec.length() < 35.0:
		_swipe_puntos.clear()
		if barra_potencia_swipe:
			barra_potencia_swipe.visible = false
		if capa_trazo_swipe:
			capa_trazo_swipe.queue_redraw()
		# Detección de Toque Corto (Tap): si el usuario tocó sobre un compañero o piso libre
		_procesar_toque_tactil_pase(p0)
		return

	_recalcular_metricas_swipe_en_vivo()
	_calcular_y_disparar_swipe(p0, p1, delta_vec)


## Detecta si un toque táctil sobre la pantalla impacta o se aproxima al colisionador de un compañero de equipo
func _detectar_companero_tocado(pos_pantalla: Vector2) -> Jugador3D:
	var cam_activa: Camera3D = camara if camara != null else get_viewport().get_camera_3d()
	if cam_activa == null or get_viewport() == null:
		return null

	var ray_origin: Vector3 = cam_activa.project_ray_origin(pos_pantalla)
	var ray_dir: Vector3 = cam_activa.project_ray_normal(pos_pantalla)

	# 1. Raycast de física directo contra colisionadores de la escena
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 45.0
	)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var resultado: Dictionary = space_state.intersect_ray(query)
	if not resultado.is_empty():
		var col: Object = resultado.get("collider")
		if col == companero_banda:
			return companero_banda
		if col == companero_frontal:
			return companero_frontal

	# 2. Tolerancia táctil por proximidad al rayo (1.35 metros) para pantallas móviles
	var companeros: Array[Jugador3D] = [companero_banda, companero_frontal]
	var mejor_candidato: Jugador3D = null
	var menor_distancia: float = 1.35

	for comp: Jugador3D in companeros:
		if comp == null or not is_instance_valid(comp):
			continue
		var pos_torso: Vector3 = comp.global_position + Vector3(0.0, 0.9, 0.0)
		var v_cam: Vector3 = pos_torso - ray_origin
		var proy: float = v_cam.dot(ray_dir)
		if proy > 0.5:
			var pt_cercano: Vector3 = ray_origin + ray_dir * proy
			var dist: float = pt_cercano.distance_to(pos_torso)
			if dist < menor_distancia:
				menor_distancia = dist
				mejor_candidato = comp

	return mejor_candidato


## Evalúa un toque simple (Tap) en la pantalla durante la fase de tiro libre:
## 1) Si colisiona con el collider de un compañero (Companero_Banda o Companero_Frontal) -> ejecutar_pase_al_pie(companero)
## 2) Si impacta sobre el piso libre Plane(Vector3.UP, 0.0) a distancia viable -> ejecutar_pase_al_hueco(hit_suelo, companero)
func _procesar_toque_tactil_pase(pos_pantalla: Vector2) -> bool:
	if estado_actual != EstadoEntrenamiento.EJECUCION:
		return false
	if _disparo_realizado or _en_secuencia_carrera_tl or _en_jugada_de_pase:
		return false
	if balon == null:
		return false

	var cam_activa: Camera3D = camara if camara != null else get_viewport().get_camera_3d()
	if cam_activa == null:
		return false

	# 1. Proyectar raycast desde la cámara activa y chequear si impacta sobre un compañero
	var receptor_pie: Jugador3D = _detectar_companero_tocado(pos_pantalla)
	if receptor_pie != null:
		ejecutar_pase_al_pie(receptor_pie)
		return true

	# 2. Si impacta sobre el piso libre (Plane(Vector3.UP, 0.0)) a una distancia viable, buscar al compañero mejor perfilado
	var ray_origin: Vector3 = cam_activa.project_ray_origin(pos_pantalla)
	var ray_dir: Vector3 = cam_activa.project_ray_normal(pos_pantalla)
	var plano_suelo: Plane = Plane(Vector3.UP, 0.0)
	var hit_suelo = plano_suelo.intersects_ray(ray_origin, ray_dir)
	if hit_suelo != null:
		var punto_suelo: Vector3 = hit_suelo
		if _es_espacio_libre_viable(punto_suelo):
			var comp_hueco: Jugador3D = _buscar_companero_mejor_perfilado(punto_suelo)
			if comp_hueco != null:
				ejecutar_pase_al_hueco(punto_suelo, comp_hueco)
				return true

	return false


## Determina si una coordenada sobre el suelo es un espacio libre viable para pase en profundidad
func _es_espacio_libre_viable(punto_suelo: Vector3) -> bool:
	if balon == null:
		return false
	# Dentro del perímetro reglamentario de la pista
	if punto_suelo.x < -18.5 or punto_suelo.x > 19.5:
		return false
	if absf(punto_suelo.z) > 9.5:
		return false
	# Pase en profundidad hacia adelante o en línea (no hacia atrás a tu propio campo)
	if punto_suelo.x < balon.global_position.x - 1.0:
		return false
	var dist_b: float = balon.global_position.distance_to(punto_suelo)
	if dist_b < 2.0 or dist_b > 25.0:
		return false
	return true


## Busca al compañero mejor perfilado para explotar el espacio libre indicado
func _buscar_companero_mejor_perfilado(punto_suelo: Vector3) -> Jugador3D:
	var candidatos: Array[Jugador3D] = []
	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if companero_banda and is_instance_valid(companero_banda) and companero_banda != pateador:
		candidatos.append(companero_banda)
	if companero_frontal and is_instance_valid(companero_frontal) and companero_frontal != pateador:
		candidatos.append(companero_frontal)

	if candidatos.is_empty():
		return null
	if candidatos.size() == 1:
		return candidatos[0]

	var mejor_candidato: Jugador3D = null
	var menor_distancia: float = 999.0
	for comp: Jugador3D in candidatos:
		var d: float = comp.global_position.distance_to(punto_suelo)
		if d < menor_distancia:
			menor_distancia = d
			mejor_candidato = comp
	return mejor_candidato


## Ejecuta un Pase al Pie:
## - El lanzador rota hacia el receptor y aplica un impulso raso directo (VEL_PASE = 8.5 m/s).
## - El receptor permanece quieto, orienta su cuerpo hacia el balón entrante y activa el área de control.
func ejecutar_pase_al_pie(companero: Jugador3D) -> void:
	if companero == null or not is_instance_valid(companero):
		return
	if _en_secuencia_carrera_tl or _en_jugada_de_pase or _disparo_realizado:
		return
	if balon == null:
		return

	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador == null or not is_instance_valid(pateador) or pateador == companero:
		return

	# Detener temporizador de 4 segundos
	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)
	if label_guia_swipe:
		label_guia_swipe.visible = false

	_en_jugada_de_pase = true
	_receptor_pase = companero
	_tipo_pase_activo = TipoPaseTL.PIE
	_pase_en_transito = false
	_tiempo_espera_pase = 0.0

	# 1. El lanzador rota hacia el receptor
	var dir_pase: Vector3 = (companero.global_position - balon.global_position).normalized()
	dir_pase.y = 0.0
	dir_pase = dir_pase.normalized()

	pateador.look_at(balon.global_position + dir_pase * 5.0, Vector3.UP)
	pateador.rotation.x = 0.0
	pateador.rotation.z = 0.0
	pateador._t_anim_patada = 0.28
	pateador.soltar_posesion()
	pateador.fijar_en_saque(false)

	# 2. El receptor activa recepción de pase entrante orientándose dinámicamente al balón
	companero.iniciar_recepcion_pase_entrante(balon, false)

	# 3. Aplica un impulso raso directo (VEL_PASE = 8.5 m/s)
	var impulso_pase: Vector3 = dir_pase * (VEL_PASE_AL_PIE * balon.mass)
	balon.sacador_autorizado = null
	if balon.has_method("liberar_pase_raso"):
		balon.liberar_pase_raso(impulso_pase, 0)
	else:
		balon.linear_damp = 0.3
		balon.angular_damp = 1.3
		balon.liberar(impulso_pase, 0, true)

	_pase_en_transito = true
	_disparo_realizado = true
	toques_en_jugada = balon.toques_en_jugada
	_transferir_control_a(companero)
	_activar_continuidad_juego_activo("¡PASE AL PIE A #%d %s!" % [companero.dorsal, companero.nombre_jugador])


## Ejecuta un Pase al Hueco (En Profundidad):
## - El balón se dispara con mayor aceleración hacia el espacio libre (VEL_PASE = 11.5 m/s).
## - El compañero seleccionado activa de inmediato una rutina de sprint (correr_al_espacio) mediante move_and_slide() hacia esa coordenada.
## - Al llegar al punto proyectado, habilita el control inmediato para rematar de primera al arco.
func ejecutar_pase_al_hueco(hit_suelo: Vector3, companero: Jugador3D) -> void:
	if companero == null or not is_instance_valid(companero):
		return
	if _en_secuencia_carrera_tl or _en_jugada_de_pase or _disparo_realizado:
		return
	if balon == null:
		return

	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador == null or not is_instance_valid(pateador) or pateador == companero:
		return

	# Detener temporizador de 4 segundos
	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)
	if label_guia_swipe:
		label_guia_swipe.visible = false

	var punto_destino: Vector3 = Vector3(hit_suelo.x, 0.0, hit_suelo.z)

	_en_jugada_de_pase = true
	_receptor_pase = companero
	_tipo_pase_activo = TipoPaseTL.HUECO
	_punto_hueco_objetivo = punto_destino
	_pase_en_transito = false
	_tiempo_espera_pase = 0.0

	# 1. El lanzador rota hacia el espacio libre en profundidad
	var dir_pase: Vector3 = (punto_destino - balon.global_position).normalized()
	dir_pase.y = 0.0
	dir_pase = dir_pase.normalized()

	pateador.look_at(balon.global_position + dir_pase * 5.0, Vector3.UP)
	pateador.rotation.x = 0.0
	pateador.rotation.z = 0.0
	pateador._t_anim_patada = 0.28
	pateador.soltar_posesion()
	pateador.fijar_en_saque(false)

	# 2. El compañero seleccionado activa de inmediato rutina de recepción al hueco en sprint
	companero.iniciar_recepcion_pase_entrante(balon, true, punto_destino)

	# 3. El balón se dispara con mayor aceleración hacia el espacio libre (VEL_PASE = 11.5 m/s)
	var impulso_pase: Vector3 = dir_pase * (VEL_PASE_AL_HUECO * balon.mass)
	balon.sacador_autorizado = null
	if balon.has_method("liberar_al_hueco"):
		balon.liberar_al_hueco(impulso_pase, punto_destino, 0, true)
	else:
		balon.linear_damp = 0.3
		balon.liberar(impulso_pase, 0, true)

	_pase_en_transito = true
	_disparo_realizado = true
	toques_en_jugada = balon.toques_en_jugada
	_transferir_control_a(companero)
	_activar_continuidad_juego_activo("¡PASE AL HUECO! CORRE #%d %s" % [companero.dorsal, companero.nombre_jugador])


## Alias de compatibilidad hacia ejecutar_pase_al_pie
func _ejecutar_pase_a_companero(receptor: Jugador3D) -> void:
	ejecutar_pase_al_pie(receptor)


## Al llegar el balón al receptor, transfiere el control a ese jugador para permitir remate directo al arco
func _completar_recepcion_pase(receptor: Jugador3D) -> void:
	_pase_en_transito = false
	_en_jugada_de_pase = false
	_disparo_realizado = false
	_tipo_pase_activo = TipoPaseTL.NINGUNO

	receptor.detener_carrera_espacio()

	var pateador_previo: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador_previo and is_instance_valid(pateador_previo) and pateador_previo != receptor:
		pateador_previo.es_controlado = false
		pateador_previo.soltar_posesion()
		pateador_previo.fijar_en_saque(false)
		pateador_previo.set_congelado(false)

	_jugador_activo_actual = receptor
	receptor.set_congelado(false)
	receptor.fijar_en_saque(false)
	receptor.es_controlado = true

	# Al llegar el balón al compañero, transfiere el control y fija posesión
	balon.capturar_por(receptor)
	toques_en_jugada = balon.toques_en_jugada

	# Orientar al receptor hacia el centro del arco rival
	var pos_arco: Vector3 = Vector3(20.0, 0.0, 0.0)
	var dir_arco: Vector3 = (pos_arco - receptor.global_position).normalized()
	dir_arco.y = 0.0
	dir_arco = dir_arco.normalized()
	receptor.look_at(receptor.global_position + dir_arco * 5.0, Vector3.UP)
	receptor.rotation.x = 0.0
	receptor.rotation.z = 0.0

	_transferir_control_a(receptor)
	_activar_continuidad_juego_activo("¡POSESIÓN DE #%d %s! ¡JUEGO ACTIVO!" % [receptor.dorsal, receptor.nombre_jugador])


## Busca al compañero más alineado con el vector de dirección especificado
func _obtener_companero_apuntado(dir: Vector3) -> Jugador3D:
	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	var candidatos: Array[Jugador3D] = []
	if companero_banda and is_instance_valid(companero_banda) and companero_banda != pateador:
		candidatos.append(companero_banda)
	if companero_frontal and is_instance_valid(companero_frontal) and companero_frontal != pateador:
		candidatos.append(companero_frontal)
	if candidatos.is_empty():
		return null
	if candidatos.size() == 1:
		return candidatos[0]

	var dir_norm: Vector3 = dir.normalized() if dir.length_squared() > 0.001 else Vector3(1.0, 0.0, 0.0)
	var mejor: Jugador3D = null
	var mejor_dot: float = -999.0
	for c: Jugador3D in candidatos:
		var pos_ref: Vector3 = balon.global_position if balon != null else global_position
		var hacia_c: Vector3 = (c.global_position - pos_ref).normalized()
		hacia_c.y = 0.0
		var dot: float = dir_norm.dot(hacia_c)
		if dot > mejor_dot:
			mejor_dot = dot
			mejor = c
	return mejor


# ==============================================================================
# PIPELINE DE ACCIONES EN VISTA CENITAL / TÁCTICA (PASE, HUECO, TIRO)
# ==============================================================================

func _on_touch_pase_solicitado(potencia: float, tipo_pase: int) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if not _vista_cenital_alterna:
		return
	_ejecutar_pase_tactico(potencia, tipo_pase)


func _on_touch_hueco_solicitado(potencia: float) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if not _vista_cenital_alterna:
		return
	_ejecutar_pase_hueco_tactico(potencia)


func _on_touch_tiro_solicitado(potencia: float, tipo_tiro: int) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if not _vista_cenital_alterna:
		return
	_ejecutar_tiro_tactico(potencia, tipo_tiro)


## Ejecuta el pase al pie en vista táctica usando el vector resultante de la flecha de puntería:
## - El lanzador ejecuta la animación de golpeo de inmediato.
## - El balón sale disparado hacia el compañero receptor.
## - El control se transfiere al receptor y se activa juego en vivo (JUEGO_ACTIVO).
func _ejecutar_pase_tactico(potencia: float, tipo_pase: int = Jugador3D.TipoPase.RASO) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if balon == null:
		return

	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador == null or not is_instance_valid(pateador):
		return

	# Detener temporizador reglamentario
	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)

	# 1. Localizar al compañero según la dirección apuntada
	var receptor: Jugador3D = _obtener_companero_apuntado(_direccion_apuntado_tactico)
	if receptor == null:
		receptor = companero_banda if companero_banda != pateador else companero_frontal

	if receptor == null or receptor == pateador:
		return

	# 2. Orientar al pateador hacia el receptor y reproducir animación de golpeo
	var dir_pase: Vector3 = (receptor.global_position - balon.global_position).normalized()
	dir_pase.y = 0.0
	dir_pase = dir_pase.normalized()
	pateador.rotation.y = atan2(-dir_pase.x, -dir_pase.z)
	pateador.rotation.x = 0.0
	pateador.rotation.z = 0.0
	pateador._t_anim_patada = 0.28
	pateador.soltar_posesion()
	pateador.fijar_en_saque(false)

	# 3. El receptor prepara recepción continua y orientada al balón
	receptor.iniciar_recepcion_pase_entrante(balon, false)

	# 4. Impulso físico directo al balón
	if balon.linear_velocity.length() < 1.0:
		var dist_rec: float = balon.global_position.distance_to(receptor.global_position)
		var fuerza: float = clampf(VEL_PASE_AL_PIE + (potencia * 3.5), 8.0, 16.5)
		var imp_vert: float = 3.85 if tipo_pase == Jugador3D.TipoPase.ELEVADO else 0.14
		var imp: Vector3 = dir_pase * (fuerza * balon.mass) + Vector3(0.0, imp_vert * balon.mass, 0.0)
		balon.sacador_autorizado = null
		if tipo_pase == Jugador3D.TipoPase.ELEVADO:
			balon.liberar_cucharita(imp, camara, 0, true)
		elif balon.has_method("liberar_pase_raso"):
			balon.liberar_pase_raso(imp, 0)
		else:
			balon.liberar(imp, 0, true)

	toques_en_jugada = balon.toques_en_jugada
	_disparo_realizado = true

	# 5. Transferir control al receptor y pasar de inmediato a JUEGO_ACTIVO
	_transferir_control_a(receptor)
	_activar_continuidad_juego_activo("¡PASE A #%d %s! ¡JUEGO ACTIVO!" % [receptor.dorsal, receptor.nombre_jugador])


## Ejecuta el pase al hueco (en profundidad) en vista táctica proyectando hacia el espacio libre:
func _ejecutar_pase_hueco_tactico(potencia: float) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if balon == null:
		return

	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador == null or not is_instance_valid(pateador):
		return

	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)

	# 1. Localizar al compañero objetivo según la dirección apuntada
	var receptor: Jugador3D = _obtener_companero_apuntado(_direccion_apuntado_tactico)
	if receptor == null:
		receptor = companero_frontal if companero_frontal != pateador else companero_banda

	if receptor == null or receptor == pateador:
		return

	# 2. Calcular punto hacia el hueco en profundidad en la dirección apuntada
	var avance: Vector3 = _direccion_apuntado_tactico.normalized()
	var punto_hueco: Vector3 = receptor.global_position + avance * (3.2 + potencia * 2.8)
	punto_hueco.x = clampf(punto_hueco.x, 2.0, 18.2)
	punto_hueco.z = clampf(punto_hueco.z, -8.6, 8.6)
	punto_hueco.y = 0.0

	# 3. Orientar al pateador hacia el hueco y animar patada
	var dir_pase: Vector3 = (punto_hueco - balon.global_position).normalized()
	dir_pase.y = 0.0
	dir_pase = dir_pase.normalized()
	pateador.rotation.y = atan2(-dir_pase.x, -dir_pase.z)
	pateador.rotation.x = 0.0
	pateador.rotation.z = 0.0
	pateador._t_anim_patada = 0.28
	pateador.soltar_posesion()
	pateador.fijar_en_saque(false)

	# 4. El receptor inicia carrera y búsqueda de intercepción al hueco
	receptor.iniciar_recepcion_pase_entrante(balon, true, punto_hueco)

	# 5. Impulso en profundidad al balón
	if balon.linear_velocity.length() < 1.0:
		var fuerza: float = clampf(VEL_PASE_AL_HUECO + (potencia * 3.5), 10.5, 17.5)
		var imp: Vector3 = dir_pase * (fuerza * balon.mass) + Vector3(0.0, 0.18 * balon.mass, 0.0)
		balon.sacador_autorizado = null
		if balon.has_method("liberar_al_hueco"):
			balon.liberar_al_hueco(imp, punto_hueco, 0, true)
		else:
			balon.liberar(imp, 0, true)

	toques_en_jugada = balon.toques_en_jugada
	_disparo_realizado = true

	# 6. Transferir control al receptor y activar continuidad en vivo
	_transferir_control_a(receptor)
	_activar_continuidad_juego_activo("¡PASE AL HUECO! CORRE #%d %s" % [receptor.dorsal, receptor.nombre_jugador])


## Ejecuta disparo directo a portería en vista táctica a lo largo de la dirección apuntada
func _ejecutar_tiro_tactico(potencia: float, tipo_tiro: int = Jugador3D.TipoTiro.NORMAL) -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	if balon == null:
		return

	var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if pateador == null or not is_instance_valid(pateador):
		return

	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)

	var dir_tiro: Vector3 = _direccion_apuntado_tactico.normalized()
	pateador.rotation.y = atan2(-dir_tiro.x, -dir_tiro.z)
	pateador.rotation.x = 0.0
	pateador.rotation.z = 0.0
	pateador._t_anim_patada = 0.28
	pateador.soltar_posesion()
	pateador.fijar_en_saque(false)

	if balon.linear_velocity.length() < 1.0:
		var rapidez: float = 14.5 + potencia * 12.0
		var elev_y: float = 0.22 if tipo_tiro != Jugador3D.TipoTiro.VASELINA else 0.55
		var imp: Vector3 = Vector3(dir_tiro.x, elev_y, dir_tiro.z).normalized() * (rapidez * balon.mass)
		balon.sacador_autorizado = null
		if tipo_tiro == Jugador3D.TipoTiro.COLOCADO:
			var signo_curva: float = 1.0 if dir_tiro.z >= 0.0 else -1.0
			var perp: Vector3 = Vector3(-dir_tiro.z, 0.0, dir_tiro.x).normalized() * signo_curva * 2.5
			balon.liberar_con_efecto_magnus(imp, perp, 0)
		elif tipo_tiro == Jugador3D.TipoTiro.VASELINA:
			balon.liberar_cucharita(imp, camara, 0, false)
		else:
			balon.liberar(imp, 0, false)

	toques_en_jugada = balon.toques_en_jugada
	_disparo_realizado = true
	_tiempo_post_impacto = 0.0
	_intentos_totales += 1
	_activar_continuidad_juego_activo("¡DISPARO A PUERTA!")


## Transforma el vector del trazo 2D al espacio 3D del mundo usando el vector frontal (`-camera.global_transform.basis.z`)
## y el vector lateral (`camera.global_transform.basis.x`) de la cámara activa, respetando la pérdida de velocidad lineal
## en tiros bombeados y activando la "Cucharita" (backspin regresivo) si el trazo vertical es muy pronunciado.
func _calcular_y_disparar_swipe(_p0: Vector2, _p1: Vector2, delta_vec: Vector2) -> void:
	var pot_norm: float = clampf(_potencia_swipe_actual, 0.35, 1.0)
	var rapidez_base: float = lerpf(14.5, 27.5, pot_norm)

	var view_rect: Rect2 = get_viewport().get_visible_rect()
	var desvio_x_norm: float = clampf(delta_vec.x / (view_rect.size.x * 0.32), -1.0, 1.0)
	var dist_vertical_px: float = maxf(25.0, -delta_vec.y)
	var altura_norm: float = clampf(dist_vertical_px / (view_rect.size.y * 0.42), 0.05, 1.0)

	# 1. Ejes de proyección de la cámara activa: frontal (-basis.z) y lateral (+basis.x)
	var cam_activa: Camera3D = camara if camara != null else get_viewport().get_camera_3d()
	var vector_frontal: Vector3 = Vector3(1.0, 0.0, 0.0)
	var vector_lateral: Vector3 = Vector3(0.0, 0.0, 1.0)
	if cam_activa != null and is_instance_valid(cam_activa):
		var frente_cam: Vector3 = -cam_activa.global_transform.basis.z
		frente_cam.y = 0.0
		if frente_cam.length_squared() > 0.001:
			vector_frontal = frente_cam.normalized()
		var lat_cam: Vector3 = cam_activa.global_transform.basis.x
		lat_cam.y = 0.0
		if lat_cam.length_squared() > 0.001:
			vector_lateral = lat_cam.normalized()

	# 2. Detectar gesto de "Cucharita" (trazo vertical muy pronunciado con elevación de vaselina/pase bombeado)
	var es_cucharita: bool = (altura_norm >= 0.84 and absf(desvio_x_norm) < 0.38 and pot_norm < 0.76)

	# 3. Pérdida de velocidad lineal proporcional a la elevación en tiros bombeados
	var factor_bombeo: float = clampf((altura_norm - 0.38) / 0.62, 0.0, 1.0)
	var rapidez_efectiva: float = rapidez_base * lerpf(1.0, 0.80, factor_bombeo)
	var comp_vertical_y: float = lerpf(0.05, 0.27, altura_norm)

	# 4. Dirección 3D combinando vector frontal, desviación lateral del trazo y apertura inicial de comba
	var dir_horiz: Vector3 = (
		vector_frontal
		+ vector_lateral * (desvio_x_norm * 0.36 - _comba_swipe_actual * 0.16)
	).normalized()
	var dir_tiro_3d: Vector3 = Vector3(dir_horiz.x, comp_vertical_y, dir_horiz.z).normalized()

	_iniciar_secuencia_carrera_y_disparo(dir_tiro_3d, rapidez_efectiva, _comba_swipe_actual, es_cucharita)

	var tw: Tween = create_tween()
	tw.tween_interval(0.35)
	tw.tween_callback(func() -> void:
		_swipe_puntos.clear()
		if barra_potencia_swipe:
			barra_potencia_swipe.visible = false
		if capa_trazo_swipe:
			capa_trazo_swipe.queue_redraw()
	)


## Inicia la secuencia de carrera previa (~0.35 s, 2-3 pasos rápidos hacia el balón) antes de aplicar el impacto físico
func _iniciar_secuencia_carrera_y_disparo(
	dir_tiro: Vector3,
	rapidez_tiro: float,
	comba: float,
	es_cucharita: bool = false
) -> void:
	if balon == null:
		return

	# Detener el temporizador reglamentario de 4 segundos al iniciar la ejecución del disparo
	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)

	if label_guia_swipe:
		label_guia_swipe.visible = false

	var pos_b: Vector3 = balon.global_position
	_dir_tiro_pendiente = dir_tiro
	_impulso_pendiente = dir_tiro * (rapidez_tiro * balon.mass)
	_comba_pendiente = comba
	_es_cucharita_pendiente = es_cucharita
	_tiempo_carrera_tl = 0.0
	_duracion_carrera_tl = 0.35
	_en_secuencia_carrera_tl = true

	var ejecutor: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if ejecutor and is_instance_valid(ejecutor):
		_pos_inicio_carrera_tl = Vector3(ejecutor.global_position.x, 0.0, ejecutor.global_position.z)
		var dir_plana: Vector3 = Vector3(dir_tiro.x, 0.0, dir_tiro.z).normalized()
		var vec_der: Vector3 = Vector3(-dir_plana.z, 0.0, dir_plana.x).normalized()
		_pos_impacto_carrera_tl = Vector3(pos_b.x, 0.0, pos_b.z) - dir_plana * 0.38 - vec_der * 0.16
		_pos_impacto_carrera_tl.y = 0.0
		ejecutor._en_carrera_tiro_libre = true
		var dir_aprox: Vector3 = (_pos_impacto_carrera_tl - _pos_inicio_carrera_tl).normalized()
		if dir_aprox.length_squared() > 0.01:
			ejecutor.rotation.y = atan2(-dir_aprox.x, -dir_aprox.z)
			ejecutor.rotation.x = 0.0
			ejecutor.rotation.z = 0.0


func _procesar_secuencia_carrera_tl(delta: float) -> void:
	_tiempo_carrera_tl += delta
	var progreso: float = clampf(_tiempo_carrera_tl / _duracion_carrera_tl, 0.0, 1.0)

	var ejecutor: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if ejecutor and is_instance_valid(ejecutor):
		var pos_interp: Vector3 = _pos_inicio_carrera_tl.lerp(_pos_impacto_carrera_tl, progreso)
		pos_interp.y = 0.0
		ejecutor._pos_anclaje_saque = pos_interp
		ejecutor.global_position = pos_interp
		ejecutor.rotation.x = 0.0
		ejecutor.rotation.z = 0.0
		if progreso >= 0.72 and ejecutor._t_anim_patada <= 0.0:
			ejecutor._en_carrera_tiro_libre = false
			ejecutor._t_anim_patada = 0.28

	if progreso >= 1.0:
		_en_secuencia_carrera_tl = false
		_aplicar_impacto_balon_post_carrera()


func _aplicar_impacto_balon_post_carrera() -> void:
	if balon == null:
		return

	_disparo_realizado = true
	_tiempo_post_impacto = 0.0
	_intentos_totales += 1

	var ejecutor: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if ejecutor and is_instance_valid(ejecutor):
		ejecutor._en_carrera_tiro_libre = false
		var pos_final_tiro: Vector3 = Vector3(ejecutor.global_position.x, 0.0, ejecutor.global_position.z)
		ejecutor.fijar_en_saque(true, pos_final_tiro)
		ejecutor._t_anim_patada = 0.28
		ejecutor.soltar_posesion()
		ejecutor.rotation.y = atan2(-_dir_tiro_pendiente.x, -_dir_tiro_pendiente.z)
		ejecutor.rotation.x = 0.0
		ejecutor.rotation.z = 0.0
		ejecutor.velocity = Vector3.ZERO

	if camara != null:
		camara.notificar_impacto_tiro_libre()

	balon.sacador_autorizado = null
	var cam_activa: Camera3D = camara if camara != null else get_viewport().get_camera_3d()
	if absf(_comba_pendiente) > 0.04 or _es_cucharita_pendiente:
		balon.liberar_tiro_libre_swipe(_impulso_pendiente, _comba_pendiente, 0, cam_activa, _es_cucharita_pendiente)
	else:
		balon.liberar(_impulso_pendiente, 0, false)
	toques_en_jugada = balon.toques_en_jugada


func _on_capa_trazo_swipe_draw() -> void:
	if capa_trazo_swipe == null or estado_actual != EstadoEntrenamiento.EJECUCION:
		return

	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var x_divisoria: float = view_size.x * 0.45

	# 1. Línea divisoria sutil de Pantalla Dividida (Izquierda < 45% Paneo | Derecha >= 45% Disparo Swipe)
	if not _disparo_realizado:
		var y_top_div: float = 75.0
		var y_bot_div: float = view_size.y - 110.0
		var y_cursor: float = y_top_div
		while y_cursor < y_bot_div:
			capa_trazo_swipe.draw_line(
				Vector2(x_divisoria, y_cursor),
				Vector2(x_divisoria, minf(y_cursor + 8.0, y_bot_div)),
				Color(0.45, 0.78, 1.0, 0.24),
				1.5,
				true
			)
			y_cursor += 18.0

	if _swipe_puntos.size() < 2:
		return

	var col_halo: Color = Color(0.18, 0.68, 1.0, 0.38)
	var col_dot: Color = Color(0.95, 0.98, 1.0, 0.95)
	var col_punta: Color = Color(1.0, 0.88, 0.25, 1.0)

	# 2. Halo translúcido siguiendo la curva del dedo
	capa_trazo_swipe.draw_polyline(_swipe_puntos, col_halo, 10.0, true)

	# 3. Guía visual de puntos (línea punteada en tiempo real)
	var dist_acum: float = 0.0
	var separacion_puntos: float = 14.0
	capa_trazo_swipe.draw_circle(_swipe_puntos[0], 4.5, col_dot)
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
			capa_trazo_swipe.draw_circle(pt_dot, 3.4, col_dot)
			d += separacion_puntos
		dist_acum = fmod(dist_acum + seg_len, separacion_puntos)

	# 4. Flecha de dirección y curvatura en la punta del trazo
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
		capa_trazo_swipe.draw_colored_polygon(pts_flecha, col_punta)

	# 5. Indicador de arco de curvatura (Efecto Magnus)
	if absf(_comba_swipe_actual) > 0.06 and _swipe_puntos.size() >= 3:
		var p_ini: Vector2 = _swipe_puntos[0]
		var p_fin: Vector2 = _swipe_puntos[-1]
		var cuerda: Vector2 = p_fin - p_ini
		if cuerda.length() > 25.0:
			var mid_cuerda: Vector2 = (p_ini + p_fin) * 0.5
			var normal_cuerda: Vector2 = Vector2(-cuerda.y, cuerda.x).normalized()
			var p_pico_curva: Vector2 = _swipe_puntos[_swipe_puntos.size() / 2]
			var color_curva: Color = Color(0.28, 0.92, 1.0, 0.85)
			capa_trazo_swipe.draw_line(mid_cuerda, p_pico_curva, color_curva, 2.2, true)
			var dir_flecha_curva: Vector2 = normal_cuerda * signf(_comba_swipe_actual)
			var perp_c: Vector2 = Vector2(-dir_flecha_curva.y, dir_flecha_curva.x)
			var c_tip: Vector2 = p_pico_curva + dir_flecha_curva * 8.0
			var c_a1: Vector2 = c_tip - dir_flecha_curva * 9.0 + perp_c * 5.5
			var c_a2: Vector2 = c_tip - dir_flecha_curva * 9.0 - perp_c * 5.5
			capa_trazo_swipe.draw_colored_polygon(PackedVector2Array([c_tip, c_a1, c_a2]), color_curva)

	# 6. Barra lateral flotante de potencia junto al inicio del trazo
	var origen_barra: Vector2 = _swipe_puntos[0] + Vector2(26.0, -36.0)
	var ancho_b: float = 10.0
	var alto_b: float = 72.0
	var rect_bg: Rect2 = Rect2(origen_barra.x, origen_barra.y, ancho_b, alto_b)
	capa_trazo_swipe.draw_rect(rect_bg, Color(0.05, 0.08, 0.14, 0.82), true)
	var fill_h: float = alto_b * clampf(_potencia_swipe_actual, 0.0, 1.0)
	var col_pot: Color = Color(0.2, 0.92, 0.45, 0.95).lerp(Color(1.0, 0.28, 0.2, 0.98), clampf(_potencia_swipe_actual, 0.0, 1.0))
	capa_trazo_swipe.draw_rect(Rect2(origen_barra.x, origen_barra.y + (alto_b - fill_h), ancho_b, fill_h), col_pot, true)
	capa_trazo_swipe.draw_rect(rect_bg, Color(0.75, 0.9, 1.0, 0.8), false, 1.5)


# ==============================================================================
# 4. BOTONES AUXILIARES Y TEMPORIZADOR DE 4 SEGUNDOS EN EJECUCIÓN
# ==============================================================================

func _actualizar_hud_cuenta_4s(segundos_restantes: float, activa: bool) -> void:
	if es_entrenamiento_activo():
		activa = false
	cuenta_regresiva_4s_actualizada.emit(segundos_restantes, activa)
	if panel_cuenta_4s:
		panel_cuenta_4s.visible = activa
	if not activa:
		return
	if barra_cuenta_4s:
		barra_cuenta_4s.max_value = tiempo_saque
		barra_cuenta_4s.value = clampf(segundos_restantes, 0.0, tiempo_saque)
	if label_cuenta_4s:
		label_cuenta_4s.text = "⏱ SAQUE REGLAMENTARIO: %.1f s" % maxf(0.0, segundos_restantes)
		if segundos_restantes <= 1.5:
			label_cuenta_4s.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3, 1.0))
		else:
			label_cuenta_4s.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0, 1.0))


func _on_timer_saque_4s_timeout() -> void:
	if es_entrenamiento_activo():
		return
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl:
		return
	_capturando_swipe = false
	_swipe_touch_id = -1
	_pan_touch_id = -1
	_swipe_puntos.clear()
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = false
	if capa_trazo_swipe:
		capa_trazo_swipe.queue_redraw()
	_actualizar_hud_cuenta_4s(0.0, false)
	_reproducir_pitido_arbitral()
	_iniciar_ciclo_fin_jugada("Tiempo agotado (4s)")


func _on_cambiar_vista_pressed() -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl or camara == null:
		return
	_aplicar_modo_vista_tactica_o_tiro(not _vista_cenital_alterna, false)


## Conmuta de forma adaptativa entre Vista Táctica/Cenital y Vista de Tiro Directo Sobre el Hombro (OTS):
## - En Vista Táctica: desactiva el lienzo de trazo swipe y activa el HUD táctil estándar de juego abierto
##   (TouchControls: joystick virtual a la izquierda y botones circulares Pase, Hueco, Tiro, Esprintar a la derecha).
## - En Vista de Tiro Directo: oculta el HUD estándar y reactiva el lienzo de trazo de tiro curvo OTS.
func _aplicar_modo_vista_tactica_o_tiro(es_tactica: bool, inmediato: bool = false) -> void:
	_vista_cenital_alterna = es_tactica
	_capturando_swipe = false
	_swipe_puntos.clear()

	# Reactivar IA de desmarques y apoyos en compañeros sin congelamiento
	if companero_banda and is_instance_valid(companero_banda):
		companero_banda.set_congelado(false)
		companero_banda.fijar_en_saque(false)
		companero_banda.es_opcion_de_pase = true
		if companero_banda.indicador_control:
			companero_banda.indicador_control.visible = true
	if companero_frontal and is_instance_valid(companero_frontal):
		companero_frontal.set_congelado(false)
		companero_frontal.fijar_en_saque(false)
		companero_frontal.es_opcion_de_pase = true
		if companero_frontal.indicador_control:
			companero_frontal.indicador_control.visible = true

	if es_tactica:
		# Vista Táctica / Cenital (Orientada a la creación de juego con HUD estándar TouchControls)
		_direccion_apuntado_tactico = _base_forward_tl
		if _indicador_cono_pase:
			_indicador_cono_pase.visible = true
		if camara:
			if inmediato:
				camara.regresar_a_broadcast(0.0)
			else:
				camara.regresar_a_broadcast(0.65)
		if capa_trazo_swipe:
			capa_trazo_swipe.visible = false
			capa_trazo_swipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
			capa_trazo_swipe.queue_redraw()
		if barra_potencia_swipe:
			barra_potencia_swipe.visible = false
		if touch_controls:
			touch_controls.visible = true
			touch_controls.establecer_modo(TouchControls.ModoHUD.ATAQUE)
			touch_controls.asignar_jugador_referencia(_jugador_activo_actual if _jugador_activo_actual else lanzador)
		if label_guia_swipe:
			label_guia_swipe.visible = true
			label_guia_swipe.text = "VISTA TÁCTICA: APUNTA CON EL JOYSTICK Y USA LOS BOTONES DE JUEGO"
		if btn_cambiar_vista:
			btn_cambiar_vista.text = "🎥 VISTA DISPARO"
	else:
		# Vista Trasera OTS (Disparo directo con trazo curvo / Magnus)
		if _indicador_cono_pase:
			_indicador_cono_pase.visible = false
		if camara:
			camara.activar_camara_tiro_libre(
				balon.global_position,
				Vector3(20.0, 0.0, 0.0),
				distancia_barrera,
				0.90,
				_base_forward_tl,
				inmediato
			)
		if touch_controls:
			touch_controls.visible = false
		if capa_trazo_swipe:
			capa_trazo_swipe.visible = true
			capa_trazo_swipe.mouse_filter = Control.MOUSE_FILTER_PASS
			capa_trazo_swipe.queue_redraw()
		if label_guia_swipe:
			label_guia_swipe.visible = true
			label_guia_swipe.text = "◀ IZQUIERDA (45%): PANEO DE CÁMARA  •  DERECHA (55%): TRAZA PARA DISPARAR Y CURVAR ▶"
		if btn_cambiar_vista:
			btn_cambiar_vista.text = "🎥 VISTA TÁCTICA"


## Activa la continuidad de juego tras rebote en la barrera o parada del arquero (Modo Entrenamiento estilo eFootball).
## Transiciona inmediatamente a 'Juego Activo' (Live Play), libera las restricciones de posición de los jugadores,
## enfoca la cámara broadcast y entrega el control libre del jugador receptor mediante el HUD estándar TouchControls.
func _activar_continuidad_juego_activo(motivo: String = "¡BALÓN EN JUEGO!") -> void:
	if estado_actual == EstadoEntrenamiento.JUEGO_ACTIVO or estado_actual == EstadoEntrenamiento.TRANSICION_FADE:
		return
	estado_actual = EstadoEntrenamiento.JUEGO_ACTIVO
	_tiempo_posesion_defensiva = 0.0
	_tiempo_sin_movimiento_balon = 0.0

	# 1. Liberar a todos los jugadores para juego abierto
	if _indicador_cono_pase:
		_indicador_cono_pase.visible = false
	if lanzador and is_instance_valid(lanzador):
		lanzador.fijar_en_saque(false)
		lanzador.set_congelado(false)
		lanzador.establecer_pose_barrera(false)
		lanzador.en_pose_barrera = false
	if companero_banda and is_instance_valid(companero_banda):
		companero_banda.set_congelado(false)
	if companero_frontal and is_instance_valid(companero_frontal):
		companero_frontal.set_congelado(false)
	for def: Jugador3D in _defensores_barrera:
		if def and is_instance_valid(def):
			def.fijar_en_saque(false)
			def.establecer_pose_barrera(false)
			def.set_congelado(false)

	# 2. Conmutar cámara a vista de transmisión / seguimiento dinámico
	if camara:
		camara.regresar_a_broadcast(0.75)

	# 3. Activar HUD estándar de juego abierto (TouchControls)
	if capa_trazo_swipe:
		capa_trazo_swipe.visible = false
		capa_trazo_swipe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if barra_potencia_swipe:
		barra_potencia_swipe.visible = false
	if touch_controls:
		touch_controls.visible = true
		touch_controls.establecer_modo(TouchControls.ModoHUD.ATAQUE)
		var receptor_cercano: Jugador3D = _jugador_activo_actual
		if receptor_cercano == null or not is_instance_valid(receptor_cercano) or not receptor_cercano.es_controlado:
			receptor_cercano = _obtener_jugador_local_mas_cercano(balon.global_position if balon else Vector3.ZERO)
		if receptor_cercano:
			_transferir_control_a(receptor_cercano)
			touch_controls.asignar_jugador_referencia(receptor_cercano)

	if label_guia_swipe:
		label_guia_swipe.visible = true
		label_guia_swipe.text = "¡JUEGO EN VIVO! DISPUTA EL REBOTE Y CONTINÚA LA JUGADA"
	if btn_cambiar_vista:
		btn_cambiar_vista.text = "🎥 VISTA JUEGO"

	_mostrar_banner_resultado(motivo)


## Retorna el jugador del equipo local más cercano a una posición 3D (para asignación rápida de control tras rebote)
func _obtener_jugador_local_mas_cercano(pos: Vector3) -> Jugador3D:
	var candidatos: Array[Jugador3D] = []
	if lanzador and is_instance_valid(lanzador): candidatos.append(lanzador)
	if companero_banda and is_instance_valid(companero_banda): candidatos.append(companero_banda)
	if companero_frontal and is_instance_valid(companero_frontal): candidatos.append(companero_frontal)
	if candidatos.is_empty():
		return null
	var mejor: Jugador3D = candidatos[0]
	var d_min: float = pos.distance_to(mejor.global_position)
	for i: int in range(1, candidatos.size()):
		var c: Jugador3D = candidatos[i]
		var d: float = pos.distance_to(c.global_position)
		if d < d_min:
			d_min = d
			mejor = c
	return mejor


## Transfiere el foco de control del usuario hacia un nuevo jugador de campo
func _transferir_control_a(nuevo_jugador: Jugador3D) -> void:
	if nuevo_jugador == null or not is_instance_valid(nuevo_jugador):
		return
	if _jugador_activo_actual != null and is_instance_valid(_jugador_activo_actual) and _jugador_activo_actual != nuevo_jugador:
		_jugador_activo_actual.es_controlado = false
		if _jugador_activo_actual.indicador_control:
			_jugador_activo_actual.indicador_control.visible = false

	_jugador_activo_actual = nuevo_jugador
	nuevo_jugador.es_controlado = true
	nuevo_jugador.set_congelado(false)
	if nuevo_jugador.indicador_control:
		nuevo_jugador.indicador_control.visible = true
	if touch_controls:
		touch_controls.asignar_jugador_referencia(nuevo_jugador)


func _on_bloqueo_barrera_realizado(defensor: Jugador3D, _zona: String) -> void:
	var nombre_def: String = "DEFENSOR"
	if defensor and is_instance_valid(defensor):
		nombre_def = defensor.nombre_jugador if defensor.nombre_jugador != "" else ("#%d" % defensor.dorsal)
	var txt: String = "¡BLOQUEO DE LA BARRERA (%s)! ¡JUEGO ACTIVO!" % nombre_def
	_ultimo_mensaje_atajada = txt
	_activar_continuidad_juego_activo(txt)


func _on_mano_en_barrera(defensor: Jugador3D, _posicion: Vector3, es_penal: bool) -> void:
	_reproducir_pitido_arbitral()
	_disparo_realizado = false
	_en_secuencia_carrera_tl = false
	var nombre_def: String = "DEFENSOR"
	if defensor and is_instance_valid(defensor):
		nombre_def = defensor.nombre_jugador if defensor.nombre_jugador != "" else ("#%d" % defensor.dorsal)
	
	var txt: String = ""
	if es_penal:
		txt = "¡MANO EN LA BARRERA DENTRO DEL ÁREA! ¡PENALTI SANCIONADO! (%s)" % nombre_def
	else:
		txt = "¡MANO EN LA BARRERA! ¡TIRO LIBRE DIRECTO! (%s)" % nombre_def

	_ultimo_mensaje_atajada = txt
	_mostrar_banner_resultado(txt)
	_iniciar_ciclo_fin_jugada(txt)


func _on_elegir_lanzador_pressed() -> void:
	if estado_actual != EstadoEntrenamiento.EJECUCION or _disparo_realizado or _en_secuencia_carrera_tl or _en_jugada_de_pase:
		return

	var candidatos: Array[Jugador3D] = []
	if lanzador: candidatos.append(lanzador)
	if companero_banda: candidatos.append(companero_banda)
	if companero_frontal: candidatos.append(companero_frontal)
	if candidatos.is_empty():
		return

	var idx_actual: int = candidatos.find(_jugador_activo_actual)
	var siguiente_idx: int = (idx_actual + 1) % candidatos.size()
	var nuevo_lanzador: Jugador3D = candidatos[siguiente_idx]

	var actual: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
	if actual != nuevo_lanzador and balon != null:
		var pos_antigua_nuevo: Vector3 = nuevo_lanzador.global_position

		var dir_arco: Vector3 = (Vector3(20.0, 0.0, 0.0) - balon.global_position).normalized()
		dir_arco.y = 0.0
		dir_arco = dir_arco.normalized()

		nuevo_lanzador.es_controlado = true
		nuevo_lanzador.set_congelado(false)
		nuevo_lanzador.global_position = balon.global_position - dir_arco * 1.5
		nuevo_lanzador.global_position.y = 0.0
		_pos_fija_lanzador = nuevo_lanzador.global_position
		nuevo_lanzador.look_at(balon.global_position + dir_arco * 5.0, Vector3.UP)
		nuevo_lanzador.rotation.x = 0.0
		nuevo_lanzador.rotation.z = 0.0
		nuevo_lanzador.fijar_en_saque(true, nuevo_lanzador.global_position)
		nuevo_lanzador.es_opcion_de_pase = false

		actual.es_controlado = false
		actual.global_position = pos_antigua_nuevo
		actual.global_position.y = 0.0
		actual.look_at(balon.global_position, Vector3.UP)
		actual.rotation.x = 0.0
		actual.rotation.z = 0.0
		actual.fijar_en_saque(false)
		actual.set_congelado(false)
		actual.es_opcion_de_pase = true

		_jugador_activo_actual = nuevo_lanzador

	_mostrar_banner_resultado("EJECUTOR: #%d %s" % [
		_jugador_activo_actual.dorsal if _jugador_activo_actual else 10,
		_jugador_activo_actual.nombre_jugador if (_jugador_activo_actual and _jugador_activo_actual.nombre_jugador != "") else "J. Álvarez"
	])


func _on_cambio_posicion_pressed() -> void:
	if estado_actual == EstadoEntrenamiento.TRANSICION_FADE or _en_secuencia_carrera_tl:
		return
	_entrar_estado_seleccion_posicion(true)


func _on_salir_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MenuEntrenamiento.tscn")


# ==============================================================================
# 5. CICLO DE FALLO / GOL Y FUNDIDO A NEGRO (FADE TO BLACK)
# ==============================================================================

func _physics_process(delta: float) -> void:
	if balon != null and is_instance_valid(balon):
		toques_en_jugada = balon.toques_en_jugada

	if estado_actual != EstadoEntrenamiento.EJECUCION and estado_actual != EstadoEntrenamiento.JUEGO_ACTIVO:
		return

	# Actualizar cuenta regresiva visual de 4 segundos solo si no es entrenamiento y el temporizador está activo
	if not es_entrenamiento_activo() and not _disparo_realizado and not _en_secuencia_carrera_tl and timer_saque_4s != null and not timer_saque_4s.is_stopped():
		_actualizar_hud_cuenta_4s(timer_saque_4s.time_left, true)

	# Mantener fija la barrera en su sitio ÚNICAMENTE durante la fase previa de saque
	if estado_actual == EstadoEntrenamiento.EJECUCION and not _disparo_realizado and not _en_jugada_de_pase:
		for i: int in range(mini(_defensores_barrera.size(), _posiciones_barrera.size())):
			var def: Jugador3D = _defensores_barrera[i]
			if def and is_instance_valid(def):
				def.global_position = _posiciones_barrera[i]
				def.velocity = Vector3.ZERO

	# Fijación del lanzador y orientación por vector en modo preparación de tiro libre
	if estado_actual == EstadoEntrenamiento.EJECUCION and not _disparo_realizado and not _en_secuencia_carrera_tl and not _en_jugada_de_pase:
		var pateador: Jugador3D = _jugador_activo_actual if _jugador_activo_actual != null else lanzador
		if pateador and is_instance_valid(pateador):
			pateador.global_position = _pos_fija_lanzador
			pateador.velocity = Vector3.ZERO
			pateador._pos_anclaje_saque = _pos_fija_lanzador
			pateador.fijar_en_saque(true, _pos_fija_lanzador)
			
			if _vista_cenital_alterna:
				# 1. Leer entrada del joystick virtual o flechas de teclado
				var joy: Vector2 = Vector2.ZERO
				if touch_controls and is_instance_valid(touch_controls):
					joy = touch_controls.obtener_direccion_joystick()
				if joy.length_squared() < 0.01:
					joy = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
				
				if joy.length_squared() > 0.04:
					_direccion_apuntado_tactico = Vector3(joy.x, 0.0, joy.y).normalized()
				
				# 2. Rotar el modelo del jugador exclusivamente sobre su eje central Y para encarar la flecha
				var angulo_apuntado: float = atan2(-_direccion_apuntado_tactico.x, -_direccion_apuntado_tactico.z)
				pateador.rotation.y = lerp_angle(pateador.rotation.y, angulo_apuntado, clampf(14.0 * delta, 0.0, 1.0))
				pateador.rotation.x = 0.0
				pateador.rotation.z = 0.0
				pateador._direccion_deseada = _direccion_apuntado_tactico
				pateador.direccion_virtual = Vector2(_direccion_apuntado_tactico.x, _direccion_apuntado_tactico.z)
		
		# 3. Actualizar indicador visual de puntería (flecha en el suelo en la posición del balón)
		if _indicador_cono_pase and is_instance_valid(_indicador_cono_pase) and balon:
			var mostrar_indicador: bool = (_vista_cenital_alterna and not _disparo_realizado and not _en_secuencia_carrera_tl and not _en_jugada_de_pase)
			_indicador_cono_pase.visible = mostrar_indicador
			if mostrar_indicador:
				_indicador_cono_pase.global_position = Vector3(balon.global_position.x, 0.02, balon.global_position.z)
				_indicador_cono_pase.rotation.y = atan2(-_direccion_apuntado_tactico.x, -_direccion_apuntado_tactico.z)
				
				# Comprobar si apunta hacia un compañero para teñir verde vs cyan
				var comp_obj: Jugador3D = _obtener_companero_apuntado(_direccion_apuntado_tactico)
				var alineado: bool = false
				if comp_obj != null and balon != null:
					var vec_comp: Vector3 = (comp_obj.global_position - balon.global_position).normalized()
					vec_comp.y = 0.0
					if _direccion_apuntado_tactico.dot(vec_comp) > 0.82:
						alineado = true
				if _mat_cono_pase:
					_mat_cono_pase.albedo_color = Color(0.25, 0.95, 0.45, 0.92) if alineado else Color(0.2, 0.85, 1.0, 0.85)
	elif _indicador_cono_pase and is_instance_valid(_indicador_cono_pase):
		_indicador_cono_pase.visible = false

	if _en_secuencia_carrera_tl:
		_procesar_secuencia_carrera_tl(delta)
		return

	# Seguimiento de pase en tránsito hacia el compañero de equipo (Pase al Pie o Pase al Hueco)
	if _en_jugada_de_pase and _pase_en_transito:
		_tiempo_espera_pase += delta
		if _receptor_pase and is_instance_valid(_receptor_pase):
			var dist_b: float = balon.global_position.distance_to(_receptor_pase.global_position)
			if _tipo_pase_activo == TipoPaseTL.HUECO:
				var dist_meta: float = _receptor_pase.global_position.distance_to(_punto_hueco_objetivo)
				if dist_meta < 0.95 or dist_b < 1.35 or (balon.esta_siendo_conducido() and balon.portador_actual == _receptor_pase):
					_completar_recepcion_pase(_receptor_pase)
					return
			else:
				_receptor_pase.look_at(balon.global_position, Vector3.UP)
				_receptor_pase.rotation.x = 0.0
				_receptor_pase.rotation.z = 0.0
				if dist_b < 1.35 or (balon.esta_siendo_conducido() and balon.portador_actual == _receptor_pase):
					_completar_recepcion_pase(_receptor_pase)
					return
		if _tiempo_espera_pase > 3.0:
			_iniciar_ciclo_fin_jugada("PASE INTERCEPTADO / CORTE DEFENSIVO")
			return
		elif _tiempo_espera_pase > 0.8 and balon.linear_velocity.length() < 0.25:
			_iniciar_ciclo_fin_jugada("PASE CORTO / INTENTO FINALIZADO")
			return
		return

	if balon == null:
		return

	if estado_actual == EstadoEntrenamiento.EJECUCION and not _disparo_realizado:
		return

	_tiempo_post_impacto += delta
	var pos_b: Vector3 = balon.global_position
	var vel_lineal: float = balon.linear_velocity.length()

	# 1. Reglas perimetrales del campo:
	# a) Línea de meta fuera de portería -> Saque de puerta
	if pos_b.x > 20.08 and absf(pos_b.z) > 1.88:
		_iniciar_ciclo_fin_jugada("¡FUERA! SAQUE DE PUERTA")
		return
	# b) Línea de meta en propio campo
	if pos_b.x < -20.08:
		_iniciar_ciclo_fin_jugada("FIN DE LA JUGADA")
		return
	# c) Líneas laterales de banda
	if absf(pos_b.z) > 10.08:
		_iniciar_ciclo_fin_jugada("¡FUERA DE BANDA!")
		return

	# 2. Posesión defensiva controlada (Rival / Arquero) > 1.5 segundos
	var rival_con_balon: bool = false
	if balon.esta_siendo_conducido() and balon.portador_actual != null and is_instance_valid(balon.portador_actual):
		if balon.portador_actual == portero_rival or balon.portador_actual in _defensores_barrera or (balon.portador_actual is Jugador3D and (balon.portador_actual as Jugador3D).equipo != Jugador3D.Equipo.LOCAL):
			rival_con_balon = true

	if rival_con_balon:
		_tiempo_posesion_defensiva += delta
		if _tiempo_posesion_defensiva >= _limite_tiempo_posesion_defensiva:
			var txt_recup: String = _ultimo_mensaje_atajada if _ultimo_mensaje_atajada != "" else "RECUPERACIÓN DEFENSIVA"
			_iniciar_ciclo_fin_jugada(txt_recup)
			return
	else:
		_tiempo_posesion_defensiva = 0.0

	# 3. Transición automática a JUEGO_ACTIVO tras rebote en barrera, poste o desvío
	if estado_actual == EstadoEntrenamiento.EJECUCION and _disparo_realizado:
		# Si tras salir hacia portería el balón desacelera tras impacto (< 8.0 m/s) o invierte su velocidad en X
		if (_tiempo_post_impacto > 0.45 and vel_lineal < 8.0) or (_tiempo_post_impacto > 0.25 and balon.linear_velocity.x < -0.2):
			_activar_continuidad_juego_activo("¡BALÓN EN JUEGO!")
			return

	# 4. Dinámica de juego activo continuo (Modo Entrenamiento estilo eFootball)
	if estado_actual == EstadoEntrenamiento.JUEGO_ACTIVO:
		# Auto-transferencia de control al compañero que tenga la posesión del balón
		if balon.esta_siendo_conducido() and balon.portador_actual != null and is_instance_valid(balon.portador_actual):
			if balon.portador_actual is Jugador3D and (balon.portador_actual as Jugador3D).equipo == Jugador3D.Equipo.LOCAL and balon.portador_actual != _jugador_activo_actual:
				_transferir_control_a(balon.portador_actual as Jugador3D)

		# Inactividad si el balón queda completamente detenido en el suelo sin posesión (> 4.5 segundos)
		if vel_lineal < 0.15 and not balon.esta_siendo_conducido():
			_tiempo_sin_movimiento_balon += delta
			if _tiempo_sin_movimiento_balon >= 4.5:
				_iniciar_ciclo_fin_jugada("BALÓN DETENIDO — FIN DE LA JUGADA")
				return
		else:
			_tiempo_sin_movimiento_balon = 0.0


## Callback ante atajadas anatómicas registradas por Balon3D o Jugador3D
func _on_atajada_realizada(zona: String, nombre_arquero: String) -> void:
	var texto_cartel: String = ""
	match zona:
		"manos":
			texto_cartel = "¡MANOTAZO SALVADOR DE %s!" % nombre_arquero
		"piernas":
			texto_cartel = "¡PARADA CON EL PIE DE %s!" % nombre_arquero
		"pecho":
			texto_cartel = "¡BLOQUEO DE PECHO DE %s!" % nombre_arquero
		"cabeza":
			texto_cartel = "¡BLOQUEO DE CABEZA DE %s!" % nombre_arquero
		_:
			texto_cartel = "¡ATAJADA DE %s!" % nombre_arquero

	_ultimo_mensaje_atajada = texto_cartel
	_mostrar_banner_resultado(texto_cartel)

	# Si no fue una captura controlada en manos del arquero (es un desvío o rebote al área),
	# transicionar inmediatamente a continuidad de juego activo
	if balon != null and not (balon.esta_siendo_conducido() and balon.portador_actual == portero_rival):
		_activar_continuidad_juego_activo(texto_cartel)


func _on_area_gol_derecha_body_entered(body: Node3D) -> void:
	if (estado_actual != EstadoEntrenamiento.EJECUCION and estado_actual != EstadoEntrenamiento.JUEGO_ACTIVO):
		return
	if body != balon:
		return

	toques_en_jugada = balon.toques_en_jugada
	if not balon.es_gol_valido_reglamentario():
		_reproducir_pitido_arbitral()
		_iniciar_ciclo_fin_jugada("¡GOL ANULADO! TIRO INDIRECTO SIN 2° TOQUE — SAQUE DE META")
		return

	_goles_convertidos += 1
	_iniciar_ciclo_fin_jugada("¡¡GOOOOL!! (%d/%d)" % [_goles_convertidos, _intentos_totales])


func _mostrar_banner_resultado(texto: String) -> void:
	if banner_resultado and label_resultado:
		label_resultado.text = texto
		banner_resultado.visible = true


func _iniciar_ciclo_fin_jugada(motivo: String) -> void:
	if estado_actual == EstadoEntrenamiento.TRANSICION_FADE:
		return

	if timer_saque_4s:
		timer_saque_4s.stop()
	_actualizar_hud_cuenta_4s(0.0, false)
	estado_actual = EstadoEntrenamiento.TRANSICION_FADE
	_disparo_realizado = false
	_en_jugada_de_pase = false
	_pase_en_transito = false
	_receptor_pase = null
	_tipo_pase_activo = TipoPaseTL.NINGUNO
	_punto_hueco_objetivo = Vector3.ZERO
	if _indicador_cono_pase:
		_indicador_cono_pase.visible = false
	if touch_controls:
		touch_controls.visible = false
	if companero_banda and is_instance_valid(companero_banda):
		companero_banda.detener_carrera_espacio()
	if companero_frontal and is_instance_valid(companero_frontal):
		companero_frontal.detener_carrera_espacio()
	_mostrar_banner_resultado(motivo)
	
	if rect_fade == null:
		_entrar_estado_seleccion_posicion(true)
		return
	
	rect_fade.visible = true
	rect_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	
	var tween: Tween = create_tween()
	tween.tween_interval(0.35)
	# Fundido a negro (alfa 0.0 -> 1.0)
	tween.tween_property(rect_fade, "color:a", 1.0, duracion_fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		if balon:
			balon.linear_velocity = Vector3.ZERO
			balon.angular_velocity = Vector3.ZERO
		_entrar_estado_seleccion_posicion(true)
	)
	tween.tween_interval(0.12)
	# Abrir fundido a negro (alfa 1.0 -> 0.0)
	tween.tween_property(rect_fade, "color:a", 0.0, duracion_fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void:
		rect_fade.visible = false
	)
