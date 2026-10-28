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
	DESMARQUE_OFENSIVO,
	PORTERO_BLOQUEO
}

enum EstadoJugador {
	ENTRADA,
	LIBRE,
	CONDUCIENDO,
	DESMARQUE_OFENSIVO,
	PRESIONANDO,
	CONTENIENDO,
	BARRIDA,
	RECUPERACION,
	PAUSA,
	IDLE_ARQUERO,
	ESTADO_PORTERO_MANOS,
	ACHIQUE_CRUZ_K,
	ATAJADA_BAJA,
	ATAJADA_MEDIA,
	SAQUE_MANO
}

enum TipoTiro {
	NORMAL,
	COLOCADO,
	VASELINA
}

enum TipoPase {
	RASO,
	ELEVADO
}

signal atajada_realizada(zona: String, nombre_arquero: String)
signal bloqueo_barrera(zona: String)
signal mano_en_barrera(posicion: Vector3, es_penal: bool)
signal llegada_espacio_libre(posicion: Vector3)

@export_group("Barrera Defensiva y Reglas")
## Si es true, sanciona mano antinatural en impactos con los brazos extendidos en T-Pose de la barrera.
## Si es false, inhabilita la capa de colisión de los brazos para emular postura con manos pegadas a la espalda.
@export var sancionar_manos_barrera: bool = true:
	set(valor):
		sancionar_manos_barrera = valor
		establecer_sancion_manos_barrera(valor)

var area_torso_piernas_cabeza: Area3D = null
var area_brazos_manos: Area3D = null

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
@export var es_arquero: bool = false:
	set(valor):
		es_arquero = valor
		if valor:
			posicion_tactica = "PORTERO"
		if is_node_ready() and valor:
			_configurar_hitboxes_anatomicas_portero()
@export var es_controlado: bool = false:
	set(valor):
		es_controlado = valor
		if is_node_ready() and indicador_control:
			indicador_control.visible = valor or es_opcion_de_pase

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
@export var radio_separacion: float = 1.45
@export var radio_dispersion_companeros: float = 2.75
@export var fuerza_separacion: float = 6.8

@export_group("Posesión y Robo")
@export var t_proteccion_recepcion: float = 1.0
@export var t_proteccion_giro: float = 0.5
@export var umbral_giro_cos: float = 0.34
@export var t_cooldown_robo_fallido: float = 1.5
@export var t_cooldown_barrida_fallida: float = 1.2
@export var t_bloqueo_recaptura: float = 0.6

@export_group("Disciplina y Sanciones (FIFA Law 12)")
var tarjetas_amarillas: int = 0
var esta_expulsado: bool = false
var _cooldown_falta_contacto: float = 0.0

@export_group("Pipeline Mid-Poly y Texture Atlas (Batching)")
## Texture Atlas de Albedo compartido por equipo (2048x2048 o 1024x1024).
@export var textura_atlas_albedo: Texture2D = null
## Normal Map del Texture Atlas para proyectar pliegues de tela, costuras y relieve muscular.
@export var textura_atlas_normal: Texture2D = null
## Mapa empaquetado ORM (Occlusion, Roughness, Metallic) opcional del Texture Atlas.
@export var textura_atlas_orm: Texture2D = null
## Variante de tono de piel y cabello en el Cuadrante 1 del Atlas (-1 = automático según dorsal).
@export_range(-1, 3, 1) var variante_aspecto_facial: int = -1
## Si está activo, recalcula normales suaves (Smooth Shading) y tangentes en mallas ArrayMesh importadas.
@export var forzar_smooth_shading: bool = true

const SHADER_JUGADOR_MIDPOLY: Shader = preload("res://shaders/jugador_midpoly.gdshader")
## Pool estático de materiales compartidos por lote de equipo (`LOCAL_CAMPO`, `LOCAL_PORTERO`, `VISITANTE_CAMPO`, `VISITANTE_PORTERO`)
## para garantizar que los jugadores del mismo equipo compartan 1 sola instancia de Material (1 Draw Call Batch).
static var _pool_materiales_atlas: Dictionary = {}
static var _textura_glb_albedo_cache: Texture2D = null
static var _textura_glb_normal_cache: Texture2D = null

# Referencias a nodos hijos y rig articulado Mid-Poly (Jugador_Futsal.glb)
@onready var collision_shape_jugador: CollisionShape3D = get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var visual: Node3D = $Visual
@onready var modelo_jugador: Node3D = get_node_or_null("Visual/ModeloJugador") as Node3D
@onready var esqueleto_humanoide: Skeleton3D = get_node_or_null("Visual/Skeleton3D") as Skeleton3D
@onready var malla_unificada_midpoly: MeshInstance3D = get_node_or_null("Visual/Skeleton3D/MallaUnificadaMidPoly") as MeshInstance3D
@onready var sombra_contacto_piso: MeshInstance3D = get_node_or_null("Visual/SombraContactoPiso") as MeshInstance3D
@onready var torso_mesh: MeshInstance3D = get_node_or_null("Visual/Torso") as MeshInstance3D
@onready var escudo_pecho: MeshInstance3D = get_node_or_null("Visual/Torso/EscudoPecho") as MeshInstance3D
@onready var label_dorsal: Label3D = (
	get_node_or_null("Visual/LabelDorsal")
	if get_node_or_null("Visual/LabelDorsal") != null
	else get_node_or_null("Visual/Torso/LabelDorsal")
) as Label3D
@onready var label_nombre: Label3D = get_node_or_null("Visual/LabelNombre") as Label3D
@onready var cuello_mesh: MeshInstance3D = get_node_or_null("Visual/Cuello") as MeshInstance3D
@onready var cabeza_mesh: MeshInstance3D = get_node_or_null("Visual/Cabeza") as MeshInstance3D
@onready var pelo_mesh: MeshInstance3D = get_node_or_null("Visual/Pelo") as MeshInstance3D
@onready var pantalones_mesh: MeshInstance3D = get_node_or_null("Visual/Pantalones") as MeshInstance3D
@onready var pivote_brazo_izq: Node3D = get_node_or_null("Visual/PivoteBrazoIzq") as Node3D
@onready var pivote_brazo_der: Node3D = get_node_or_null("Visual/PivoteBrazoDer") as Node3D
@onready var manga_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoIzq/MangaIzq") as MeshInstance3D
@onready var manga_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoDer/MangaDer") as MeshInstance3D
@onready var brazo_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoIzq/BrazoIzq") as MeshInstance3D
@onready var brazo_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoDer/BrazoDer") as MeshInstance3D
@onready var mano_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoIzq/ManoIzq") as MeshInstance3D
@onready var mano_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivoteBrazoDer/ManoDer") as MeshInstance3D
@onready var pivote_pierna_izq: Node3D = get_node_or_null("Visual/PivotePiernaIzq") as Node3D
@onready var pivote_pierna_der: Node3D = get_node_or_null("Visual/PivotePiernaDer") as Node3D
@onready var muslo_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/MusloIzq") as MeshInstance3D
@onready var muslo_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/MusloDer") as MeshInstance3D
@onready var pierna_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/PiernaIzq") as MeshInstance3D
@onready var pierna_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/PiernaDer") as MeshInstance3D
@onready var media_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/MediaIzq") as MeshInstance3D
@onready var media_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/MediaDer") as MeshInstance3D
@onready var botin_izq_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaIzq/BotinIzq") as MeshInstance3D
@onready var botin_der_mesh: MeshInstance3D = get_node_or_null("Visual/PivotePiernaDer/BotinDer") as MeshInstance3D
@onready var indicador_control: MeshInstance3D = get_node_or_null("Visual/IndicadorControl") as MeshInstance3D
@onready var flecha_guia_pase: Node3D = get_node_or_null("FlechaGuiaPase") as Node3D
@onready var cuerpo_flecha_mesh: MeshInstance3D = get_node_or_null("FlechaGuiaPase/CuerpoFlecha") as MeshInstance3D
@onready var punta_flecha_mesh: MeshInstance3D = get_node_or_null("FlechaGuiaPase/PuntaFlecha") as MeshInstance3D
@onready var control_balon_area: Area3D = $ControlBalonArea
@onready var punto_conduccion: Marker3D = $PuntoConduccion
var _mat_flecha_guia: StandardMaterial3D = null

# Hitboxes anatómicas de contacto para el arquero (Manos, Pecho, Piernas, Cabeza)
var area_manos: Area3D = null
var area_pecho: Area3D = null
var area_piernas: Area3D = null
var area_cabeza: Area3D = null

# Nodos de malla y huesos descubiertos dinámicamente dentro de `Visual/ModeloJugador` (Jugador_Futsal.glb)
var malla_cuerpo_glb: MeshInstance3D = null
var malla_camiseta_glb: MeshInstance3D = null
var malla_short_glb: MeshInstance3D = null
var malla_medias_glb: MeshInstance3D = null
var malla_botines_glb: MeshInstance3D = null
var malla_pelo_glb: MeshInstance3D = null
var malla_pestanas_glb: MeshInstance3D = null

var _idx_left_arm: int = -1
var _idx_right_arm: int = -1
var _idx_left_forearm: int = -1
var _idx_right_forearm: int = -1
var _idx_left_upleg: int = -1
var _idx_right_upleg: int = -1
var _idx_left_leg: int = -1
var _idx_right_leg: int = -1
var _idx_spine: int = -1

var _rest_left_arm: Quaternion = Quaternion.IDENTITY
var _rest_right_arm: Quaternion = Quaternion.IDENTITY
var _rest_left_forearm: Quaternion = Quaternion.IDENTITY
var _rest_right_forearm: Quaternion = Quaternion.IDENTITY
var _rest_left_upleg: Quaternion = Quaternion.IDENTITY
var _rest_right_upleg: Quaternion = Quaternion.IDENTITY
var _rest_left_leg: Quaternion = Quaternion.IDENTITY
var _rest_right_leg: Quaternion = Quaternion.IDENTITY
var _rest_spine: Quaternion = Quaternion.IDENTITY

# Ángulos interpolados para animación esqueletal humanoide
var _ang_pierna_izq_x: float = 0.0
var _ang_pierna_der_x: float = 0.0
var _ang_pierna_izq_z: float = 0.0
var _ang_pierna_der_z: float = 0.0
var _ang_rodilla_izq_x: float = 0.0
var _ang_rodilla_der_x: float = 0.0
var _ang_brazo_izq_x: float = 0.0
var _ang_brazo_der_x: float = 0.0
var _ang_brazo_izq_z: float = 0.0
var _ang_brazo_der_z: float = 0.0
var _ang_codo_izq_z: float = 0.35
var _ang_codo_der_z: float = -0.35

# Estado de máquina de estados y dinámica
var _estado: EstadoJugador = EstadoJugador.LIBRE
var _congelado: bool = false
var _en_entrada: bool = false
var _destino_entrada: Vector3 = Vector3.ZERO
var _en_posicion_saque: bool = false
var _pos_anclaje_saque: Vector3 = Vector3.ZERO
var tiene_posesion: bool = false
var tiene_balon_en_manos: bool = false
var _balon_referencia: Balon3D = null
var _direccion_deseada: Vector3 = Vector3.ZERO
var _tiempo_inmunidad_robo: float = 0.0
var _posicion_tactica_inicial: Vector3 = Vector3.ZERO
var _estado_ia: EstadoIA = EstadoIA.REPOSO

# Variables de animación procedural de extremidades y estados reglamentarios del arquero de futsal
var _fase_carrera: float = 0.0
var _t_anim_patada: float = 0.0
var _t_anim_atajada: float = 0.0
var _en_achique_cruz_k: bool = false
var _tipo_atajada_actual: EstadoJugador = EstadoJugador.ATAJADA_BAJA
var _lado_atajada: float = 0.0 # -1.0: Izquierda, 1.0: Derecha, 0.0: Frontal
var _t_anim_saque_mano: float = 0.0
var en_pose_barrera: bool = false
var _en_carrera_tiro_libre: bool = false

# Objetivo predictivo de recepción de pase al hueco y mecánica "Pasa y Corre" (Give-and-Go)
var _t_carrera_hueco: float = 0.0
var _objetivo_carrera_hueco: Vector3 = Vector3.ZERO
var es_opcion_de_pase: bool = false
var _t_desmarque_ofensivo: float = 0.0
var _objetivo_desmarque_ofensivo: Vector3 = Vector3.ZERO

# Rutina de recepción activa y anticipación de pases
var _esperando_recepcion_pase: bool = false
var _tiempo_espera_recepcion: float = 0.0
var _es_recepcion_hueco: bool = false
var _punto_recepcion_hueco: Vector3 = Vector3.ZERO

# Rutina de sprint al espacio libre en reanudaciones y tiro libre
var _corriendo_al_espacio: bool = false
var _objetivo_carrera_espacio: Vector3 = Vector3.ZERO
var _t_carrera_espacio: float = 0.0
var _duracion_carrera_espacio: float = 2.5

# Variables de giro, bloqueo y aturdimiento
var _dir_previa: Vector3 = Vector3.ZERO
var _t_bloqueo_recaptura: float = 0.0
var _t_aturdimiento: float = 0.0

# Estado de barrida y defensa
var _en_barrida: bool = false
var _tiempo_barrida: float = 0.0
var _barrida_toco_balon: bool = false
var _barrida_cometio_falta: bool = false
var _cooldown_intento_robo: float = 0.0
var _cooldown_decision_ia: float = 0.0
var _tiempo_paradon_reciente: float = 0.0
var _orden_presion_equipo: bool = false

# Entrada móvil / teclado
var direccion_virtual: Vector2 = Vector2.ZERO
var sprint_activo: bool = false
var _sprint_tactil_mantenido: bool = false
var _presion_sprint_defensivo: bool = false


func _ready() -> void:
	if name.begins_with("Vis_"):
		equipo = Equipo.VISITANTE
	elif name.begins_with("Local_"):
		equipo = Equipo.LOCAL
	
	_posicion_tactica_inicial = global_position
	
	if indicador_control:
		indicador_control.visible = es_controlado
	
	_inicializar_flecha_guia_pase()
	_inicializar_nodos_modelo_glb()
	_configurar_geometria_y_sombras_midpoly()
	_cargar_ficha_futsal_3d()
	_asignar_grupos()
	_conectar_sensores_balon()
	_actualizar_colores_uniforme()
	
	if name.findn("portero") != -1 or dorsal == 1 or posicion_tactica == "PORTERO":
		posicion_tactica = "PORTERO"
		es_arquero = true
	
	if es_arquero:
		_configurar_hitboxes_anatomicas_portero()
	else:
		_configurar_hitboxes_barrera()
	
	call_deferred("_configurar_excepcion_colision_balon")


func _inicializar_flecha_guia_pase() -> void:
	if flecha_guia_pase == null:
		return
	_mat_flecha_guia = StandardMaterial3D.new()
	_mat_flecha_guia.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_flecha_guia.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_flecha_guia.albedo_color = Color(0.35, 0.88, 1.0, 0.58)
	if cuerpo_flecha_mesh:
		cuerpo_flecha_mesh.material_override = _mat_flecha_guia
	if punta_flecha_mesh:
		punta_flecha_mesh.material_override = _mat_flecha_guia
	flecha_guia_pase.visible = es_controlado


## Descubre e inicializa las mallas (`Ch38_*`), texturas embebidas y huesos del modelo importado `Jugador_Futsal.glb`
func _inicializar_nodos_modelo_glb() -> void:
	if modelo_jugador == null and visual != null:
		modelo_jugador = visual.get_node_or_null("ModeloJugador") as Node3D
	if modelo_jugador == null:
		return

	# Detener AnimationPlayer estático (T-Pose de 2 cuadros) si existe para permitir control procedural del Skeleton3D
	var anim_player: AnimationPlayer = modelo_jugador.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		anim_player.stop()

	if esqueleto_humanoide == null:
		esqueleto_humanoide = modelo_jugador.find_child("Skeleton3D", true, false) as Skeleton3D

	# Localizar las mallas del futbolista humanoide dentro de Jugador_Futsal.glb
	malla_cuerpo_glb = modelo_jugador.find_child("Ch38_Body", true, false) as MeshInstance3D
	malla_camiseta_glb = modelo_jugador.find_child("Ch38_Shirt", true, false) as MeshInstance3D
	malla_short_glb = modelo_jugador.find_child("Ch38_Shorts", true, false) as MeshInstance3D
	malla_medias_glb = modelo_jugador.find_child("Ch38_Socks", true, false) as MeshInstance3D
	malla_botines_glb = modelo_jugador.find_child("Ch38_Shoes", true, false) as MeshInstance3D
	malla_pelo_glb = modelo_jugador.find_child("Ch38_Hair", true, false) as MeshInstance3D
	malla_pestanas_glb = modelo_jugador.find_child("Ch38_Eyelashes", true, false) as MeshInstance3D

	# Mantener compatibilidad con referencias que consulten `torso_mesh`, `cabeza_mesh` o `pantalones_mesh`
	if torso_mesh == null and malla_camiseta_glb != null:
		torso_mesh = malla_camiseta_glb
	if cabeza_mesh == null and malla_cuerpo_glb != null:
		cabeza_mesh = malla_cuerpo_glb
	if pantalones_mesh == null and malla_short_glb != null:
		pantalones_mesh = malla_short_glb
	if pelo_mesh == null and malla_pelo_glb != null:
		pelo_mesh = malla_pelo_glb

	# Extraer y cachear las texturas Diffuse y Normal embebidas en el .glb antes de aplicar material_override
	if _textura_glb_albedo_cache == null and malla_cuerpo_glb != null and malla_cuerpo_glb.mesh != null:
		if malla_cuerpo_glb.mesh.get_surface_count() > 0:
			var mat_orig: Material = malla_cuerpo_glb.get_active_material(0)
			if mat_orig == null:
				mat_orig = malla_cuerpo_glb.mesh.surface_get_material(0)
			if mat_orig is BaseMaterial3D:
				var std_mat: BaseMaterial3D = mat_orig as BaseMaterial3D
				if std_mat.albedo_texture != null:
					_textura_glb_albedo_cache = std_mat.albedo_texture
				if std_mat.normal_texture != null:
					_textura_glb_normal_cache = std_mat.normal_texture

	# Cachear índices y poses de reposo de los huesos principales del rig Mixamo (`mixamorig5:*`)
	if esqueleto_humanoide != null:
		_idx_left_arm = _buscar_hueso_humanoide(["mixamorig5:LeftArm", "mixamorig:LeftArm", "LeftArm"])
		_idx_right_arm = _buscar_hueso_humanoide(["mixamorig5:RightArm", "mixamorig:RightArm", "RightArm"])
		_idx_left_forearm = _buscar_hueso_humanoide(["mixamorig5:LeftForeArm", "mixamorig:LeftForeArm", "LeftForeArm"])
		_idx_right_forearm = _buscar_hueso_humanoide(["mixamorig5:RightForeArm", "mixamorig:RightForeArm", "RightForeArm"])
		_idx_left_upleg = _buscar_hueso_humanoide(["mixamorig5:LeftUpLeg", "mixamorig:LeftUpLeg", "LeftUpLeg"])
		_idx_right_upleg = _buscar_hueso_humanoide(["mixamorig5:RightUpLeg", "mixamorig:RightUpLeg", "RightUpLeg"])
		_idx_left_leg = _buscar_hueso_humanoide(["mixamorig5:LeftLeg", "mixamorig:LeftLeg", "LeftLeg"])
		_idx_right_leg = _buscar_hueso_humanoide(["mixamorig5:RightLeg", "mixamorig:RightLeg", "RightLeg"])
		_idx_spine = _buscar_hueso_humanoide(["mixamorig5:Spine1", "mixamorig5:Spine", "mixamorig:Spine1", "Spine1", "Spine"])

		if _idx_left_arm >= 0:
			_rest_left_arm = esqueleto_humanoide.get_bone_rest(_idx_left_arm).basis.get_rotation_quaternion()
		if _idx_right_arm >= 0:
			_rest_right_arm = esqueleto_humanoide.get_bone_rest(_idx_right_arm).basis.get_rotation_quaternion()
		if _idx_left_forearm >= 0:
			_rest_left_forearm = esqueleto_humanoide.get_bone_rest(_idx_left_forearm).basis.get_rotation_quaternion()
		if _idx_right_forearm >= 0:
			_rest_right_forearm = esqueleto_humanoide.get_bone_rest(_idx_right_forearm).basis.get_rotation_quaternion()
		if _idx_left_upleg >= 0:
			_rest_left_upleg = esqueleto_humanoide.get_bone_rest(_idx_left_upleg).basis.get_rotation_quaternion()
		if _idx_right_upleg >= 0:
			_rest_right_upleg = esqueleto_humanoide.get_bone_rest(_idx_right_upleg).basis.get_rotation_quaternion()
		if _idx_left_leg >= 0:
			_rest_left_leg = esqueleto_humanoide.get_bone_rest(_idx_left_leg).basis.get_rotation_quaternion()
		if _idx_right_leg >= 0:
			_rest_right_leg = esqueleto_humanoide.get_bone_rest(_idx_right_leg).basis.get_rotation_quaternion()
		if _idx_spine >= 0:
			_rest_spine = esqueleto_humanoide.get_bone_rest(_idx_spine).basis.get_rotation_quaternion()

		# Relajar brazos inicialmente desde la T-Pose hacia los costados del torso
		_aplicar_pose_esqueleto_actual()


func _buscar_hueso_humanoide(candidatos: Array[String]) -> int:
	if esqueleto_humanoide == null:
		return -1
	for nombre_hueso: String in candidatos:
		var idx: int = esqueleto_humanoide.find_bone(nombre_hueso)
		if idx >= 0:
			return idx
	return -1


func _aplicar_rotacion_hueso(idx: int, rest_q: Quaternion, rot_x: float, rot_y: float, rot_z: float) -> void:
	if esqueleto_humanoide == null or idx < 0:
		return
	var delta_q: Quaternion = Quaternion.from_euler(Vector3(rot_x, rot_y, rot_z))
	esqueleto_humanoide.set_bone_pose_rotation(idx, rest_q * delta_q)


## Aplica los ángulos articulados actuales al `Skeleton3D` humanoide (`mixamorig5:*`),
## bajando los brazos de la T-pose (+1.18 rad en X local) y articulando hombros, codos, muslos y rodillas.
func _aplicar_pose_esqueleto_actual() -> void:
	if esqueleto_humanoide == null:
		return
	# En el rig Mixamo de Jugador_Futsal.glb:
	# - LeftArm / RightArm: +X baja los brazos desde T-pose (0.0) hacia el costado del cuerpo (~1.18 rad).
	#   La abducción lateral (abrir brazos en Z) reduce esa bajada en X.
	#   El balanceo frontal/trasero ocurre en el eje Z local del brazo (+Z en LeftArm avanza, -Z en RightArm avanza).
	var bajada_izq_x: float = clampf(1.18 - clampf(_ang_brazo_izq_z, -0.4, 1.15) * 0.72, 0.15, 1.35)
	var bajada_der_x: float = clampf(1.18 - clampf(-_ang_brazo_der_z, -0.4, 1.15) * 0.72, 0.15, 1.35)
	var swing_izq_z: float = _ang_brazo_izq_x * 0.78
	var swing_der_z: float = -_ang_brazo_der_x * 0.78

	_aplicar_rotacion_hueso(_idx_left_arm, _rest_left_arm, bajada_izq_x, 0.0, swing_izq_z)
	_aplicar_rotacion_hueso(_idx_right_arm, _rest_right_arm, bajada_der_x, 0.0, swing_der_z)
	_aplicar_rotacion_hueso(_idx_left_forearm, _rest_left_forearm, 0.0, 0.0, _ang_codo_izq_z)
	_aplicar_rotacion_hueso(_idx_right_forearm, _rest_right_forearm, 0.0, 0.0, _ang_codo_der_z)

	# Muslos (LeftUpLeg / RightUpLeg): +X avanza el muslo, -X lo retrasa, Z abre lateralmente
	_aplicar_rotacion_hueso(_idx_left_upleg, _rest_left_upleg, _ang_pierna_izq_x, 0.0, _ang_pierna_izq_z)
	_aplicar_rotacion_hueso(_idx_right_upleg, _rest_right_upleg, _ang_pierna_der_x, 0.0, _ang_pierna_der_z)

	# Rodillas (LeftLeg / RightLeg): -X flexiona la rodilla hacia atrás
	_aplicar_rotacion_hueso(_idx_left_leg, _rest_left_leg, _ang_rodilla_izq_x, 0.0, 0.0)
	_aplicar_rotacion_hueso(_idx_right_leg, _rest_right_leg, _ang_rodilla_der_x, 0.0, 0.0)


## Fuerza la actualización de equipo, ficha de datos, grupos y materiales 3D del uniforme
func aplicar_uniforme_equipo(forzar_equipo: int = -1) -> void:
	if forzar_equipo == 0:
		equipo = Equipo.LOCAL
	elif forzar_equipo == 1:
		equipo = Equipo.VISITANTE
	_cargar_ficha_futsal_3d()
	_asignar_grupos()
	_actualizar_colores_uniforme()
	if posicion_tactica == "PORTERO":
		es_arquero = true
	if es_arquero:
		_configurar_hitboxes_anatomicas_portero()
	else:
		_configurar_hitboxes_barrera()


## Inicia la secuencia cinemática de entrada trotando desde la zona de banquillos hacia la posición inicial
func iniciar_entrada_cancha(pos_salida_banquillo: Vector3) -> void:
	_en_entrada = true
	_congelado = false
	_en_posicion_saque = false
	_destino_entrada = _posicion_tactica_inicial
	global_position = pos_salida_banquillo
	velocity = Vector3.ZERO
	_estado = EstadoJugador.ENTRADA


## Finaliza la secuencia de entrada dejando al jugador alineado en su posición táctica inicial
func finalizar_entrada_cancha() -> void:
	_en_entrada = false
	global_position = _posicion_tactica_inicial
	velocity = Vector3.ZERO
	_direccion_deseada = Vector3.ZERO
	var dir_frente: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	rotation.y = atan2(-dir_frente.x, -dir_frente.z)
	_actualizar_estado()


## Asigna un punto proyectado en el espacio libre para que el receptor corra al hueco
func asignar_objetivo_carrera_hueco(punto_destino: Vector3, duracion: float = 1.2) -> void:
	_objetivo_carrera_hueco = punto_destino
	_t_carrera_hueco = duracion


## Activa de inmediato la rutina de sprint (move_and_slide) hacia una coordenada en el espacio libre
## para ganarle la espalda a la barrera defensiva en jugadas a balón parado
func correr_al_espacio(punto_suelo: Vector3, duracion: float = 2.5) -> void:
	fijar_en_saque(false)
	set_congelado(false)
	_corriendo_al_espacio = true
	_objetivo_carrera_espacio = Vector3(punto_suelo.x, 0.0, punto_suelo.z)
	_duracion_carrera_espacio = duracion
	_t_carrera_espacio = 0.0
	sprint_activo = true
	_sprint_tactil_mantenido = true
	es_opcion_de_pase = true
	if indicador_control:
		indicador_control.visible = true


## Detiene la rutina de sprint al espacio libre y estabiliza al jugador
func detener_carrera_espacio() -> void:
	_corriendo_al_espacio = false
	sprint_activo = false
	_sprint_tactil_mantenido = false
	velocity = Vector3.ZERO
	_direccion_deseada = Vector3.ZERO


## Orienta el cuerpo hacia el balón entrante y activa el área de recepción y control (Pase al Pie)
func orientar_y_preparar_recepcion(pos_balon: Vector3) -> void:
	var b: Balon3D = _obtener_balon_juego()
	iniciar_recepcion_pase_entrante(b, false)


## Prepara al compañero receptor para reconocer la trayectoria del balón,
## orientarse en tiempo real hacia él y desplazarse activamente a controlarlo
func iniciar_recepcion_pase_entrante(nodo_balon: Balon3D, es_hueco: bool = false, punto_hueco: Vector3 = Vector3.ZERO) -> void:
	detener_carrera_espacio()
	_en_posicion_saque = false
	set_congelado(false)
	_esperando_recepcion_pase = true
	_tiempo_espera_recepcion = 3.2
	_es_recepcion_hueco = es_hueco
	_punto_recepcion_hueco = punto_hueco
	if nodo_balon != null:
		_balon_referencia = nodo_balon
	es_opcion_de_pase = true
	if indicador_control:
		indicador_control.visible = true
	
	if es_hueco:
		correr_al_espacio(punto_hueco, 2.8)
	else:
		sprint_activo = false
		if nodo_balon != null:
			var dir_b: Vector3 = nodo_balon.global_position - global_position
			dir_b.y = 0.0
			if dir_b.length_squared() > 0.001:
				var dir_n: Vector3 = dir_b.normalized()
				look_at(global_position + dir_n * 5.0, Vector3.UP)
				rotation.x = 0.0
				rotation.z = 0.0


## Procesa la anticipación activa de recepción: el receptor reconoce la trayectoria del balón,
## se orienta en tiempo real (Look-At) y se desplaza hacia el balón para controlar de primera
func _procesar_recepcion_pase(delta: float) -> void:
	_tiempo_espera_recepcion -= delta
	if _tiempo_espera_recepcion <= 0.0 or tiene_posesion:
		_esperando_recepcion_pase = false
		return
	
	var nodo_b: Balon3D = _obtener_balon_juego()
	if nodo_b == null or not is_instance_valid(nodo_b):
		_esperando_recepcion_pase = false
		return
	
	var pos_b: Vector3 = nodo_b.global_position
	var vec_hacia_b: Vector3 = pos_b - global_position
	vec_hacia_b.y = 0.0
	var dist_b: float = vec_hacia_b.length()
	
	# 1. Orientación continua e inmediata hacia el balón entrante (Look-At)
	if dist_b > 0.05:
		var dir_mira_b: Vector3 = vec_hacia_b.normalized()
		var ang_b: float = atan2(-dir_mira_b.x, -dir_mira_b.z)
		rotation.y = lerp_angle(rotation.y, ang_b, clampf(20.0 * delta, 0.0, 1.0))
		rotation.x = 0.0
		rotation.z = 0.0
	
	# 2. Desplazamiento activo hacia el balón (intercepción / control en avance)
	var joy: Vector2 = direccion_virtual
	if joy.length_squared() > 0.15:
		# Si el usuario ya está dirigiendo el joystick, respetar la intención del usuario
		_direccion_deseada = Vector3(joy.x, 0.0, joy.y).normalized()
		sprint_activo = _sprint_tactil_mantenido
	else:
		if not _es_recepcion_hueco:
			if dist_b > 0.40:
				_direccion_deseada = vec_hacia_b.normalized()
				sprint_activo = dist_b > 2.2
			else:
				_direccion_deseada = Vector3.ZERO
				sprint_activo = false
		else:
			var hacia_punto: Vector3 = _punto_recepcion_hueco - global_position
			hacia_punto.y = 0.0
			if hacia_punto.length() > 0.35:
				_direccion_deseada = hacia_punto.normalized()
				sprint_activo = true
			else:
				_direccion_deseada = Vector3.ZERO
				sprint_activo = false
	
	# 3. Control automático al alcanzar radio de recepción
	if dist_b < 1.25 and puede_tomar_balon():
		tomar_posesion(nodo_b)
		_esperando_recepcion_pase = false


## Procesa la cinemática de carrera a máxima velocidad hacia la coordenada de desmarque al hueco
func _procesar_carrera_al_espacio(delta: float) -> void:
	_t_carrera_espacio += delta
	var diff: Vector3 = _objetivo_carrera_espacio - global_position
	diff.y = 0.0
	var dist: float = diff.length()
	
	# Captura anticipada del balón si ya está al alcance durante la carrera
	var nodo_b: Balon3D = _obtener_balon_juego()
	if nodo_b and is_instance_valid(nodo_b):
		var dist_b: float = global_position.distance_to(nodo_b.global_position)
		if dist_b < 1.25 and puede_tomar_balon():
			tomar_posesion(nodo_b)
			_corriendo_al_espacio = false
			return
	
	if dist > 0.35 and _t_carrera_espacio < _duracion_carrera_espacio:
		var dir_carrera: Vector3 = diff / dist
		_direccion_deseada = dir_carrera
		sprint_activo = true
		_sprint_tactil_mantenido = true
		
		var angulo_obj: float = atan2(-dir_carrera.x, -dir_carrera.z)
		rotation.y = lerp_angle(rotation.y, angulo_obj, clampf(velocidad_giro * delta * 1.4, 0.0, 1.0))
		rotation.x = 0.0
		rotation.z = 0.0
	else:
		_corriendo_al_espacio = false
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false
		_sprint_tactil_mantenido = false
		llegada_espacio_libre.emit(global_position)


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
		var pos_suelo: Vector3 = Vector3(pos_anclaje.x, 0.0, pos_anclaje.z)
		_pos_anclaje_saque = pos_suelo
		global_position = pos_suelo
		rotation.x = 0.0
		rotation.z = 0.0
		velocity = Vector3.ZERO
	else:
		en_pose_barrera = false
		_en_carrera_tiro_libre = false


## Activa o desactiva la postura compacta de defensor en barrera de tiro libre
## y conmuta las hitboxes segmentadas de Torso/Piernas/Cabeza vs Brazos/Manos
func establecer_pose_barrera(activo: bool) -> void:
	en_pose_barrera = activo
	_configurar_hitboxes_barrera()

	if area_torso_piernas_cabeza:
		area_torso_piernas_cabeza.monitoring = activo
		area_torso_piernas_cabeza.monitorable = activo
		area_torso_piernas_cabeza.collision_mask = 1 if activo else 0

	if area_brazos_manos:
		var hab_manos: bool = activo and sancionar_manos_barrera
		area_brazos_manos.monitoring = hab_manos
		area_brazos_manos.monitorable = hab_manos
		area_brazos_manos.collision_mask = 1 if hab_manos else 0

	var balon: Balon3D = _obtener_balon_juego()
	if balon and is_instance_valid(balon):
		# Mantenemos la excepción de colisión con el CharacterBody3D para que sean las hitboxes anatómicas
		# dedicadas ("Torso_Legs_Head" vs "Arms_Hands") las que procesen el impacto
		add_collision_exception_with(balon)
		balon.add_collision_exception_with(self)


func _configurar_excepcion_colision_balon() -> void:
	var balon: Balon3D = _obtener_balon_juego()
	if balon and is_instance_valid(balon):
		add_collision_exception_with(balon)
		balon.add_collision_exception_with(self)


func _asignar_grupos() -> void:
	add_to_group("jugadores_futsal")
	if equipo == Equipo.LOCAL:
		if is_in_group("equipo_visitante"):
			remove_from_group("equipo_visitante")
		add_to_group("equipo_local")
	else:
		if is_in_group("equipo_local"):
			remove_from_group("equipo_local")
		add_to_group("equipo_visitante")
	
	if es_controlado:
		add_to_group("jugador_activo")


## Retorna true si el jugador está en condiciones físicas de controlar el balón
func puede_tomar_balon() -> bool:
	if _t_bloqueo_recaptura > 0.0 or _t_aturdimiento > 0.0 or _congelado or _en_entrada or en_pose_barrera:
		return false
	if _en_posicion_saque:
		var balon_saque: Balon3D = _obtener_balon_juego()
		if balon_saque == null or balon_saque.sacador_autorizado != self:
			return false
	var balon: Balon3D = _obtener_balon_juego()
	if balon == null or not is_instance_valid(balon):
		return false
	if balon.has_method("puede_ser_capturado_por") and not balon.puede_ser_capturado_por(self):
		return false
	if balon.has_method("puede_ser_capturado") and not balon.puede_ser_capturado():
		return false
	return true


## Desbloquea inmediatamente la recaptura del balón cuando otro jugador (compañero o rival) toca la pelota
func desbloquear_recaptura() -> void:
	_t_bloqueo_recaptura = 0.0
	if control_balon_area:
		control_balon_area.set_deferred("monitoring", true)


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
	return _tiempo_inmunidad_robo <= 0.0 and not tiene_balon_en_manos and not _en_posicion_saque and not _en_entrada


## Deriva el estado dinámico del jugador según entrada, posesión, estados dedicados del arquero, barrida, desmarque y defensa
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
	
	# Si el jugador recibe el balón o el rival recupera la posesión, concluir estado de Pasa y Corre o recepción
	if tiene_posesion:
		if _t_desmarque_ofensivo > 0.0:
			_t_desmarque_ofensivo = 0.0
		if _esperando_recepcion_pase:
			_esperando_recepcion_pase = false
	
	if indicador_control:
		indicador_control.visible = es_controlado or es_opcion_de_pase
	
	# El arquero NUNCA debe quedar controlado por el usuario si no tiene el balón
	if posicion_tactica == "PORTERO" and es_controlado and not tiene_posesion:
		cambiar_a_mas_cercano_al_balon(false)
	
	if _en_entrada:
		_estado = EstadoJugador.ENTRADA
		return
	
	if _congelado:
		_estado = EstadoJugador.PAUSA
		return
	
	# Estados dedicados exclusivos del arquero de futsal
	if posicion_tactica == "PORTERO":
		if tiene_balon_en_manos:
			_estado = EstadoJugador.ESTADO_PORTERO_MANOS
			return
		if _t_anim_atajada > 0.0:
			_estado = _tipo_atajada_actual
			return
		if _t_anim_saque_mano > 0.0:
			_estado = EstadoJugador.SAQUE_MANO
			return
		if _en_achique_cruz_k:
			_estado = EstadoJugador.ACHIQUE_CRUZ_K
			return
		_estado = EstadoJugador.IDLE_ARQUERO
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
	
	if _t_desmarque_ofensivo > 0.0:
		_estado = EstadoJugador.DESMARQUE_OFENSIVO
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
	if esta_expulsado:
		return
	
	if _t_anim_patada > 0.0:
		_t_anim_patada -= delta
	if _t_anim_atajada > 0.0:
		_t_anim_atajada -= delta
	if _t_anim_saque_mano > 0.0:
		_t_anim_saque_mano -= delta
	if _t_carrera_hueco > 0.0:
		_t_carrera_hueco -= delta
	if _t_desmarque_ofensivo > 0.0:
		_t_desmarque_ofensivo -= delta
		if _t_desmarque_ofensivo <= 0.0:
			es_opcion_de_pase = false
	if _cooldown_falta_contacto > 0.0:
		_cooldown_falta_contacto -= delta
	
	_actualizar_estado()
	
	match _estado:
		EstadoJugador.PAUSA:
			velocity = Vector3.ZERO
			_animar_extremidades(delta)
			return
		EstadoJugador.ENTRADA:
			_procesar_movimiento_entrada(delta)
			move_and_slide()
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
		if _t_bloqueo_recaptura <= 0.0:
			if control_balon_area:
				control_balon_area.set_deferred("monitoring", true)
	if _t_aturdimiento > 0.0:
		_t_aturdimiento -= delta
	
	# Protección contra caídas al vacío y anclaje al nivel del suelo
	if global_position.y < 0.0:
		global_position.y = 0.0
		velocity.y = 0.0
	
	# Aislar posición del arquero con balón fuera de la línea de gol (impide autogol accidental)
	var gk_bloqueado_con_manos: bool = (posicion_tactica == "PORTERO" and (tiene_balon_en_manos or _estado == EstadoJugador.ESTADO_PORTERO_MANOS))
	if gk_bloqueado_con_manos:
		if equipo == Equipo.LOCAL:
			global_position.x = clampf(global_position.x, -18.2, -14.5)
		else:
			global_position.x = clampf(global_position.x, 14.5, 18.2)
		global_position.z = clampf(global_position.z, -2.8, 2.8)
	elif posicion_tactica == "PORTERO" and tiene_posesion:
		# Si el arquero controla el balón con los pies (tras cesión de compañero), mantener margen de seguridad frente a su línea de meta
		global_position.x = clampf(global_position.x, -18.3, 18.3)
		global_position.z = clampf(global_position.z, -9.8, 9.8)
	else:
		global_position.x = clampf(global_position.x, -20.2, 20.2)
		global_position.z = clampf(global_position.z, -11.9, 10.5)
	
	# Gravedad básica
	if not is_on_floor():
		velocity.y -= gravedad * delta
	else:
		velocity.y = 0.0
	
	match _estado:
		EstadoJugador.BARRIDA:
			_tiempo_barrida -= delta
			if not _barrida_toco_balon:
				if _chequear_impacto_barrida():
					_barrida_toco_balon = true
				elif not _barrida_cometio_falta and _chequear_falta_barrida():
					_barrida_cometio_falta = true
			if _tiempo_barrida <= 0.0:
				_en_barrida = false
				if not _barrida_toco_balon:
					_t_aturdimiento = t_cooldown_barrida_fallida
		_:
			if _corriendo_al_espacio:
				_procesar_carrera_al_espacio(delta)
			elif _esperando_recepcion_pase:
				_procesar_recepcion_pase(delta)
			elif es_controlado:
				_procesar_input_jugador()
			else:
				_procesar_ia_tactica(delta)
			
			_aplicar_movimiento(delta)
	
	if _en_posicion_saque:
		_pos_anclaje_saque.y = 0.0
		global_position = _pos_anclaje_saque
		rotation.x = 0.0
		rotation.z = 0.0
		velocity = Vector3.ZERO
	elif gk_bloqueado_con_manos:
		velocity = Vector3.ZERO
	else:
		move_and_slide()
		_chequear_contacto_fisico_falta()
	
	# Captura proactiva del balón libre
	_chequear_proximidad_balon()
	
	_gestionar_conduccion_y_robos(delta)
	_actualizar_flecha_guia_pase(delta)
	_animar_extremidades(delta)
	if es_arquero:
		_actualizar_hitboxes_portero()


## Actualiza la Flecha Guía de Pase y Apuntamiento en el plano XZ bajo los pies del jugador controlado:
## - Se orienta dinámicamente hacia la dirección del joystick.
## - Si detecta un compañero viable en el cono de visión, resalta su color/longitud y se orienta hacia el receptor previsto.
func _actualizar_flecha_guia_pase(delta: float) -> void:
	if flecha_guia_pase == null:
		return
	
	if not es_controlado or _en_entrada or _congelado:
		flecha_guia_pase.visible = false
		return
	
	flecha_guia_pase.visible = true
	
	var dir_frente: Vector3 = -global_transform.basis.z
	dir_frente.y = 0.0
	if dir_frente.length_squared() < 0.001:
		dir_frente = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	else:
		dir_frente = dir_frente.normalized()
	
	var dir_apuntado: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else dir_frente
	dir_apuntado.y = 0.0
	dir_apuntado = dir_apuntado.normalized() if dir_apuntado.length_squared() > 0.001 else dir_frente
	
	var receptor_viable: Jugador3D = null
	if tiene_posesion or _en_posicion_saque:
		var candidato: Jugador3D = _buscar_mejor_receptor(dir_apuntado)
		if candidato != null:
			var hacia_cand: Vector3 = candidato.global_position - global_position
			hacia_cand.y = 0.0
			if hacia_cand.length_squared() > 0.04:
				var dir_cand: Vector3 = hacia_cand.normalized()
				if dir_apuntado.dot(dir_cand) >= 0.28:
					receptor_viable = candidato
	
	if receptor_viable != null:
		var dir_receptor: Vector3 = receptor_viable.global_position - global_position
		dir_receptor.y = 0.0
		dir_receptor = dir_receptor.normalized() if dir_receptor.length_squared() > 0.001 else dir_apuntado
		var angulo_receptor: float = atan2(-dir_receptor.x, -dir_receptor.z)
		flecha_guia_pase.global_rotation = Vector3(
			0.0,
			lerp_angle(flecha_guia_pase.global_rotation.y, angulo_receptor, clampf(18.0 * delta, 0.0, 1.0)),
			0.0
		)
		flecha_guia_pase.scale = flecha_guia_pase.scale.lerp(Vector3(1.15, 1.0, 1.26), clampf(14.0 * delta, 0.0, 1.0))
		if _mat_flecha_guia != null:
			_mat_flecha_guia.albedo_color = Color(0.22, 1.0, 0.56, 0.90)
	else:
		var angulo_joy: float = atan2(-dir_apuntado.x, -dir_apuntado.z)
		flecha_guia_pase.global_rotation = Vector3(
			0.0,
			lerp_angle(flecha_guia_pase.global_rotation.y, angulo_joy, clampf(20.0 * delta, 0.0, 1.0)),
			0.0
		)
		flecha_guia_pase.scale = flecha_guia_pase.scale.lerp(Vector3(1.0, 1.0, 1.0), clampf(14.0 * delta, 0.0, 1.0))
		if _mat_flecha_guia != null:
			_mat_flecha_guia.albedo_color = Color(0.35, 0.88, 1.0, 0.58)


## Desplaza al jugador trotando desde el banquillo hacia su posición inicial durante el estado ENTRADA
func _procesar_movimiento_entrada(delta: float) -> void:
	var hacia_destino: Vector3 = _destino_entrada - global_position
	hacia_destino.y = 0.0
	var dist: float = hacia_destino.length()
	if dist > 0.22:
		var dir: Vector3 = hacia_destino.normalized()
		_direccion_deseada = dir
		var vel_trote: float = 4.35
		velocity.x = dir.x * vel_trote
		velocity.z = dir.z * vel_trote
		var angulo_obj: float = atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, angulo_obj, clampf(14.0 * delta, 0.0, 1.0))
	else:
		finalizar_entrada_cancha()



func _conectar_sensores_balon() -> void:
	if control_balon_area:
		control_balon_area.body_entered.connect(_on_control_balon_area_body_entered)
		control_balon_area.body_exited.connect(_on_control_balon_area_body_exited)


func _on_control_balon_area_body_entered(body: Node3D) -> void:
	if body is Balon3D:
		var balon: Balon3D = body as Balon3D
		if _t_bloqueo_recaptura > 0.0 or not puede_tomar_balon():
			return
		if not balon.esta_siendo_conducido() and not balon.esta_fuera_de_juego:
			if posicion_tactica == "PORTERO":
				Portero.procesar_recepcion(self, balon)
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
	if tiene_posesion or _en_barrida or _t_bloqueo_recaptura > 0.0:
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
			if posicion_tactica == "PORTERO":
				Portero.procesar_recepcion(self, balon)
			else:
				tomar_posesion(balon)


## Toma posesión magnética del balón con escudo protector inicial
func tomar_posesion(balon: Balon3D) -> void:
	if balon == null:
		return
	detener_carrera_espacio()
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


## El portero atrapa con las manos (ESTADO_PORTERO_MANOS):
## Verifica primero la Regla de Cesión al Portero (si fue pase con el pie de un compañero, sanciona Tiro Libre Indirecto).
## Congela de inmediato toda traslación física (velocity = Vector3.ZERO), aísla la posición respecto al arco
## y habilita únicamente rotación con el joystick para apuntar el saque con la mano.
func atrapar_con_manos(balon: Balon3D) -> void:
	if balon == null:
		return
	
	# Regla Futsal: Si el balón proviene de cesión intencional con el pie de un compañero, sancionar Tiro Libre Indirecto
	if Portero.verificar_y_sancionar_cesion_manos(self, balon):
		return
	
	_balon_referencia = balon
	tiene_posesion = true
	tiene_balon_en_manos = true
	_en_achique_cruz_k = false
	_estado = EstadoJugador.ESTADO_PORTERO_MANOS
	velocity = Vector3.ZERO
	_direccion_deseada = Vector3.ZERO
	
	# Asegurar posición interior segura lejos de AreaGolIzquierda / AreaGolDerecha
	if equipo == Equipo.LOCAL:
		global_position.x = clampf(global_position.x, -18.2, -14.5)
	else:
		global_position.x = clampf(global_position.x, 14.5, 18.2)
	global_position.z = clampf(global_position.z, -2.8, 2.8)
	
	var dir_frente: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	rotation.y = atan2(-dir_frente.x, -dir_frente.z)
	
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
			if j_act.indicador_control:
				j_act.indicador_control.visible = false
			j_act.remove_from_group("jugador_activo")
	
	es_controlado = true
	direccion_virtual = dir_heredada
	_sprint_tactil_mantenido = sprint_heredado
	sprint_activo = sprint_heredado
	if not is_in_group("jugador_activo"):
		add_to_group("jugador_activo")
	if indicador_control:
		indicador_control.visible = true
	
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam and "ruta_jugador_activo" in cam:
		cam.ruta_jugador_activo = cam.get_path_to(self)
	
	var tc: TouchControls = get_tree().get_first_node_in_group("touch_controls") as TouchControls
	if tc and is_instance_valid(tc):
		tc.asignar_jugador_referencia(self)


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
		if facing_portador.dot(dir_hacia_ladron) < -0.15 and randf() < 0.16:
			_notificar_falta_arbitro(self, portador.global_position, portador, false)


## Mantiene el balón en los pies o manos del portador
func _gestionar_conduccion_y_robos(delta: float) -> void:
	if not tiene_posesion or _balon_referencia == null or not is_instance_valid(_balon_referencia):
		return
	if not _balon_referencia.esta_siendo_conducido() or _balon_referencia.portador_actual != self:
		tiene_posesion = false
		tiene_balon_en_manos = false
		return
	
	if tiene_balon_en_manos:
		# Balón a la altura de las manos / pecho del arquero, siempre proyectado hacia la cancha
		var pos_manos: Vector3 = global_position - global_transform.basis.z * 0.58 + Vector3(0.0, 0.85, 0.0)
		if equipo == Equipo.LOCAL:
			pos_manos.x = maxf(pos_manos.x, -18.0)
		else:
			pos_manos.x = minf(pos_manos.x, 18.0)
		_balon_referencia.conducir_hacia(pos_manos, delta, 99.0, self)
	elif not _en_posicion_saque:
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
	
	# En Modo Sin Balón (Defensa), el botón ESPRINTAR + PRESIÓN orienta o asiste la carrera rápida hacia el balón
	if _presion_sprint_defensivo and not tiene_posesion and not _en_posicion_saque:
		var balon_def: Balon3D = _obtener_balon_juego()
		if balon_def and is_instance_valid(balon_def):
			var hacia_balon: Vector3 = balon_def.global_position - global_position
			hacia_balon.y = 0.0
			if hacia_balon.length_squared() > 0.04:
				var dir_presion: Vector3 = hacia_balon.normalized()
				if _direccion_deseada.length_squared() > 0.01:
					_direccion_deseada = (_direccion_deseada * 0.55 + dir_presion * 0.45).normalized()
				else:
					_direccion_deseada = dir_presion
	
	# Nota Reglamentaria: En SAQUE_CENTRO (y demás saques), mover el joystick solo rota al sacador para apuntar;
	# el movimiento libre y el reloj neto solo se desbloquean al soltar el balón mediante PASE o HUECO.
	
	# Protección adicional al girar bruscamente con posesión
	if tiene_posesion and _dir_previa.length() > 0.5 and _dir_previa.dot(_direccion_deseada) < umbral_giro_cos:
		_tiempo_inmunidad_robo = maxf(_tiempo_inmunidad_robo, t_proteccion_giro)
	_dir_previa = _direccion_deseada


# ==============================================================================
# ACCIONES CONTEXTUALES Y GESTOS SWIPE / FLICK (FC MOBILE / EFOOTBALL)
# ==============================================================================

## Acción del Botón 3 (Ataque: TIRO [Normal, Colocado Swipe Down, Vaselina Swipe Up] | Defensa: ENTRADA / BARRIDA)
func accion_principal_presionada(potencia: float = 0.5, tipo_tiro: int = TipoTiro.NORMAL) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if tiene_posesion or _en_posicion_saque or (dist_balon < 1.95 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and (puede_tomar_balon() or _en_posicion_saque):
			tomar_posesion(balon)
		ejecutar_tiro(potencia, tipo_tiro)
	else:
		ejecutar_barrida()


## Acción del Botón 1 (Ataque: PASE [Raso Normal, Elevado/Sombrerito Swipe Up] | Defensa: CAMBIAR JUGADOR)
func accion_pase_presionada(potencia: float = 0.5, tipo_pase: int = TipoPase.RASO) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var es_saque: bool = (balon != null and (balon.sacador_autorizado == self or _en_posicion_saque))
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if es_saque or tiene_posesion or (dist_balon < 2.5 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and (puede_tomar_balon() or es_saque):
			tomar_posesion(balon)
		ejecutar_pase(potencia, tipo_pase)
	else:
		cambiar_a_mas_cercano_al_balon()


## Acción del Botón 2 (Ataque: HUECO [Conos de Pase Predictivos] | Defensa: PRESIÓN 2° DEFENSOR)
func accion_hueco_presionada(potencia: float = 0.5) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var es_saque: bool = (balon != null and (balon.sacador_autorizado == self or _en_posicion_saque))
	var dist_balon: float = global_position.distance_to(balon.global_position) if balon else 99.0
	
	if es_saque or tiene_posesion or (dist_balon < 2.5 and (balon and not balon.esta_siendo_conducido())):
		if not tiene_posesion and balon and (puede_tomar_balon() or es_saque):
			tomar_posesion(balon)
		ejecutar_pase_hueco(potencia)
	else:
		ordenar_presion_equipo()


## Disparo a portería con soporte para:
## - TipoTiro.NORMAL: Disparo seco y potente directo a puerta.
## - TipoTiro.COLOCADO (Swipe Down): Tiro de calidad con efecto Magnus (curva buscando el segundo poste, menor velocidad lineal y mayor precisión).
## - TipoTiro.VASELINA (Swipe Up): Picadita parabólica suave para superar al arquero en achiques.
func ejecutar_tiro(potencia: float = 0.5, tipo_tiro: int = TipoTiro.NORMAL) -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var es_saque: bool = (balon != null and (balon.sacador_autorizado == self or _en_posicion_saque))
	if es_saque and not tiene_posesion:
		if balon != null:
			tomar_posesion(balon)
	elif _en_posicion_saque and not tiene_posesion:
		var b: Balon3D = _obtener_balon_juego()
		if b != null:
			tomar_posesion(b)
	if not tiene_posesion or _balon_referencia == null:
		return
	
	# Si el arquero tiene el balón en las manos (ESTADO_PORTERO_MANOS / SAQUE_META), obligatoriamente distribuye con la mano
	if tiene_balon_en_manos:
		ejecutar_pase(potencia, TipoPase.RASO)
		return
	
	# En SAQUE_CENTRO, la regla exige obligatoriamente reanudar mediante pase a un compañero
	var gestor_sc: Node = get_tree().get_first_node_in_group("gestor_partido")
	if gestor_sc != null and gestor_sc.has_method("es_saque_centro_activo") and gestor_sc.es_saque_centro_activo():
		ejecutar_pase(potencia, TipoPase.RASO)
		return
	
	var era_portero_local: bool = (posicion_tactica == "PORTERO" and equipo == Equipo.LOCAL and es_controlado)
	var arco_x: float = 20.0 if equipo == Equipo.LOCAL else -20.0
	var objetivo_z: float = 0.0
	
	# Porterías de 3.7m de ancho (postes en ±1.85m): en Tiro Colocado buscar siempre el segundo poste (más lejano al tirador)
	if tipo_tiro == TipoTiro.COLOCADO:
		objetivo_z = -1.58 if global_position.z >= 0.0 else 1.58
		if abs(_direccion_deseada.z) > 0.25:
			objetivo_z = 1.58 if _direccion_deseada.z > 0.0 else -1.58
	else:
		if _direccion_deseada.z < -0.18:
			objetivo_z = -1.48
		elif _direccion_deseada.z > 0.18:
			objetivo_z = 1.48
		else:
			objetivo_z = -1.12 if randf() > 0.5 else 1.12
	
	var presion: float = calcular_presion_rival()
	var error_dispersion: float = ((99.0 - precision_tiro) / 99.0 * 0.28) + (presion * 0.22)
	if tipo_tiro == TipoTiro.COLOCADO:
		# Mayor precisión en Tiro de Calidad
		error_dispersion *= 0.42
	
	var z_colocado: float = clampf(objetivo_z + randf_range(-error_dispersion, error_dispersion), -1.72, 1.72)
	var pos_origen_tiro: Vector3 = _balon_referencia.global_position
	
	_en_posicion_saque = false
	_t_anim_patada = 0.28
	soltar_posesion()
	_t_bloqueo_recaptura = 1.0
	if control_balon_area:
		control_balon_area.set_deferred("monitoring", false)
	
	if tipo_tiro == TipoTiro.COLOCADO:
		# SWIPE DOWN -> TIRO COLOCADO CON CURVA BALÍSTICA NATURAL HACIA EL SEGUNDO POSTE:
		# 1. Vector inicial dirigido hacia el poste opuesto con ligera apertura inicial.
		# 2. Fuerza lateral moderada con decaimiento exponencial (F_magnus * e^(-lambda * t)) que cierra al poste sin girar en círculos.
		var signo_curva: float = 1.0 if z_colocado >= 0.0 else -1.0
		var z_apertura: float = z_colocado - signo_curva * 0.68
		var elevacion_colocado: float = lerpf(0.32, 1.05, clampf(potencia, 0.0, 0.90))
		var destino_poste_lejano: Vector3 = Vector3(arco_x, elevacion_colocado, z_apertura)
		var dir_tiro: Vector3 = (destino_poste_lejano - pos_origen_tiro).normalized()
		
		var fuerza_colocado: float = (11.2 + (potencia_tiro / 99.0) * 5.0 + (potencia * 12.5)) * 0.86
		var impulso_colocado: Vector3 = dir_tiro * fuerza_colocado + Vector3(0.0, 0.68 + potencia * 0.42, 0.0)
		
		var dir_plana_avance: Vector3 = Vector3(dir_tiro.x, 0.0, dir_tiro.z).normalized()
		var dir_perp_a_poste: Vector3 = Vector3(0.0, 0.0, signo_curva)
		# Componente puramente perpendicular al eje inicial de avance en el plano XZ
		dir_perp_a_poste = (dir_perp_a_poste - dir_plana_avance * dir_perp_a_poste.dot(dir_plana_avance)).normalized()
		var magnitud_curva: float = 2.35 + (precision_tiro / 99.0) * 0.85
		_balon_referencia.liberar_con_efecto_magnus(impulso_colocado, dir_perp_a_poste * magnitud_curva, int(equipo))
		if equipo == Equipo.LOCAL:
			_emitir_anuncio_hud("¡TIRO COLOCADO CON ROSCA!")
	elif tipo_tiro == TipoTiro.VASELINA:
		# SWIPE UP -> MECÁNICA DE "CUCHARITA" (VASELINA / PICADITA PARABÓLICA CON BACKSPIN REGRESIVO):
		# Reduce la fuerza frontal (Z) un 40-50% a favor de la componente vertical (Y) y aplica torque negativo en X de cámara
		var destino_vaselina: Vector3 = Vector3(arco_x, 0.4, clampf(z_colocado * 0.75, -1.35, 1.35))
		var diff_arco: Vector3 = destino_vaselina - pos_origen_tiro
		diff_arco.y = 0.0
		var dist_arco: float = diff_arco.length()
		var dir_plana_vas: Vector3 = diff_arco.normalized() if dist_arco > 0.1 else Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
		var fuerza_base_vas: float = clampf(dist_arco * 0.65 + 4.2 + potencia * 3.2, 6.8, 14.5) * _balon_referencia.mass
		var fuerza_vert_vas: float = clampf(2.4 + potencia * 1.1, 2.4, 3.6)
		var impulso_vaselina: Vector3 = dir_plana_vas * fuerza_base_vas + Vector3(0.0, fuerza_vert_vas, 0.0)
		var cam_vas: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
		_balon_referencia.liberar_cucharita(impulso_vaselina, cam_vas, int(equipo), false)
		if equipo == Equipo.LOCAL:
			_emitir_anuncio_hud("¡VASELINA / PICADITA!")
	else:
		# TOQUE NORMAL -> DISPARO SECO Y POTENTE DIRECTO A PUERTA
		var elevacion_y: float = lerpf(0.28, 1.45, clampf(potencia, 0.0, 0.92))
		if potencia > 0.92:
			error_dispersion += 0.18
			elevacion_y = randf_range(1.35, 2.05)
		var destino_tiro: Vector3 = Vector3(arco_x, elevacion_y, z_colocado)
		var vector_tiro: Vector3 = (destino_tiro - pos_origen_tiro).normalized()
		var fuerza_total: float = 10.5 + (potencia_tiro / 99.0) * 5.5 + (potencia * 15.5)
		var impulso_final: Vector3 = vector_tiro * fuerza_total + Vector3(0.0, 0.65 + potencia * 0.55, 0.0)
		_balon_referencia.liberar(impulso_final, int(equipo), false)
	
	if era_portero_local:
		cambiar_a_mas_cercano_al_balon(false)


## Pase con soporte para:
## - TipoPase.RASO: Pase raso firme directo al pie.
## - TipoPase.ELEVADO (Swipe Up): Pase bombeado / sombrerito por el aire para superar piernas estiradas de defensores.
## - Activa automáticamente la mecánica "Pasa y Corre" (Give-and-Go / DESMARQUE_OFENSIVO) en el pasador.
## - Registra si es cesión con el pie de un jugador de campo (Regla Futsal: el portero no puede agarrarla con las manos).
func ejecutar_pase(potencia: float = 0.5, tipo_pase: int = TipoPase.RASO) -> void:
	var b_saque: Balon3D = _obtener_balon_juego()
	var es_saque: bool = (b_saque != null and (b_saque.sacador_autorizado == self or _en_posicion_saque))
	if es_saque:
		_balon_referencia = b_saque
		tiene_posesion = true
		_en_posicion_saque = false
	elif _en_posicion_saque and not tiene_posesion:
		if b_saque != null:
			tomar_posesion(b_saque)
	if not tiene_posesion or _balon_referencia == null:
		return
	
	var era_saque_mano: bool = tiene_balon_en_manos
	var es_pase_pie_campo: bool = (not era_saque_mano and posicion_tactica != "PORTERO")
	var era_controlado_local: bool = (equipo == Equipo.LOCAL and es_controlado and posicion_tactica != "PORTERO")
	var dir_intencion_joystick: Vector3 = _direccion_deseada
	
	var dir_por_defecto: Vector3 = -global_transform.basis.z.normalized()
	if posicion_tactica == "PORTERO":
		dir_por_defecto = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	
	var dir_busqueda: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else dir_por_defecto
	var mejor_companero: Jugador3D = _buscar_mejor_receptor(dir_busqueda)
	
	var presion: float = calcular_presion_rival()
	var stat_precision: float = gk_saque if era_saque_mano else vision_pase
	var error_total_rad: float = ((99.0 - stat_precision) / 99.0 * 0.12) + (presion * 0.12)
	var desvio_angulo: float = randf_range(-error_total_rad, error_total_rad)
	
	# Potencia escalada por carga de botón
	var fuerza_pase: float = 8.0 + (potencia * 11.5) + (stat_precision / 99.0) * 2.5
	
	_en_posicion_saque = false
	if era_saque_mano:
		_t_anim_saque_mano = 0.38
		_estado = EstadoJugador.SAQUE_MANO
	else:
		_t_anim_patada = 0.26
	
	if mejor_companero != null:
		var target: Vector3 = mejor_companero.global_position + (mejor_companero.velocity * 0.22)
		var pos_origen_balon: Vector3 = global_position + Vector3(0.0, 0.25, 0.0) if era_saque_mano else _balon_referencia.global_position
		if era_saque_mano:
			_balon_referencia.global_position = pos_origen_balon
		var dist_comp: float = pos_origen_balon.distance_to(target)
		var dir_pase: Vector3 = (target - pos_origen_balon).rotated(Vector3.UP, desvio_angulo).normalized()
		dir_pase.y = 0.0
		dir_pase = dir_pase.normalized()
		
		# Velocidad de pase raso firme y fluida (~8.5 a 11.5 m/s) para futsal reglamentario
		var vel_pase: float = clampf(8.8 + (potencia * 2.2) + (dist_comp * 0.10), 8.5, 11.5)
		if era_saque_mano:
			vel_pase = clampf(7.5 + (potencia * 3.0) + (dist_comp * 0.12), 7.5, 12.5)
		
		var impulso_vertical: float = 0.14
		if tipo_pase == TipoPase.ELEVADO:
			# SWIPE UP -> PASE ELEVADO / SOMBRERITO por encima de defensores
			vel_pase = clampf(dist_comp * 0.78 + 4.2 + potencia * 3.5, 6.5, 15.0)
			impulso_vertical = clampf(3.85 + dist_comp * 0.12 + potencia * 1.25, 3.85, 6.2)
			if equipo == Equipo.LOCAL:
				_emitir_anuncio_hud("¡PASE ELEVADO / SOMBRERITO!")
		
		soltar_posesion()
		_t_bloqueo_recaptura = 1.0
		if control_balon_area:
			control_balon_area.set_deferred("monitoring", false)
		
		# Notificar inmediatamente al compañero receptor para anticipar y dar 1-2 pasos al encuentro del balón
		mejor_companero.iniciar_recepcion_pase_entrante(_balon_referencia, false)
		
		if tipo_pase == TipoPase.ELEVADO:
			var cam_pase: Camera3D = get_viewport().get_camera_3d() if get_viewport() else null
			var imp_base_elev: Vector3 = dir_pase * (vel_pase * _balon_referencia.mass * 1.35) + Vector3(0.0, impulso_vertical * _balon_referencia.mass, 0.0)
			_balon_referencia.liberar_cucharita(imp_base_elev, cam_pase, int(equipo), es_pase_pie_campo)
		else:
			var impulso_pase: Vector3 = dir_pase * (vel_pase * _balon_referencia.mass)
			_balon_referencia.liberar_pase_raso(impulso_pase, int(equipo), es_pase_pie_campo, self)
		
		# Si estábamos en saque de centro, notificar inmediatamente al gestor de partido para inicio de reloj neto
		var gestor_sc: Node = get_tree().get_first_node_in_group("gestor_partido")
		if gestor_sc and gestor_sc.has_method("notificar_toque_saque_centro"):
			gestor_sc.notificar_toque_saque_centro()
		
		# Activar mecánica "Pasa y Corre" (Give-and-Go) antes de transferir el control al receptor
		if era_controlado_local and mejor_companero.posicion_tactica != "PORTERO":
			iniciar_pasa_y_corre(dir_intencion_joystick)
		
		# Transferir el foco y control de usuario de inmediato al receptor
		if equipo == Equipo.LOCAL and es_controlado:
			if mejor_companero.posicion_tactica != "PORTERO":
				_transferir_control_a(mejor_companero)
			elif posicion_tactica == "PORTERO":
				cambiar_a_mas_cercano_al_balon(false)
	else:
		var dir_defecto: Vector3 = dir_busqueda.rotated(Vector3.UP, desvio_angulo).normalized()
		var vel_def: float = clampf(8.8 + potencia * 2.2, 8.5, 11.0)
		var imp_def: Vector3 = dir_defecto * (vel_def * _balon_referencia.mass)
		if era_saque_mano:
			_balon_referencia.global_position = global_position + Vector3(0.0, 0.25, 0.0)
		soltar_posesion()
		_t_bloqueo_recaptura = 1.0
		if control_balon_area:
			control_balon_area.set_deferred("monitoring", false)
		_balon_referencia.liberar_pase_raso(imp_def, int(equipo), es_pase_pie_campo, self)
		var gestor_sc2: Node = get_tree().get_first_node_in_group("gestor_partido")
		if gestor_sc2 and gestor_sc2.has_method("notificar_toque_saque_centro"):
			gestor_sc2.notificar_toque_saque_centro()
		if posicion_tactica == "PORTERO" and equipo == Equipo.LOCAL and es_controlado:
			cambiar_a_mas_cercano_al_balon(false)


# ==============================================================================
# 3. MECÁNICA "PASA Y CORRE" (DESMARQUE INTELIGENTE / GIVE-AND-GO)
# ==============================================================================

## Activa el estado DESMARQUE_OFENSIVO durante 2.6s tras dar un pase:
## El pasador no frena ni vuelve a su ancla pasiva; ataca el espacio libre superando la línea del defensor
## más cercano y levanta la bandera es_opcion_de_pase = true con prioridad alta para cámara y asistencia.
func iniciar_pasa_y_corre(dir_intencion: Vector3 = Vector3.ZERO) -> void:
	if posicion_tactica == "PORTERO":
		return
	
	# Limpiar banderas previas en otros compañeros para concentrar la prioridad en este corredor
	var grupo_propio: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
	var companeros: Array[Node] = get_tree().get_nodes_in_group(grupo_propio)
	for n: Node in companeros:
		var comp: Jugador3D = n as Jugador3D
		if comp and comp != self:
			comp.es_opcion_de_pase = false
			comp._t_desmarque_ofensivo = 0.0
	
	_t_desmarque_ofensivo = 2.65
	es_opcion_de_pase = true
	_estado = EstadoJugador.DESMARQUE_OFENSIVO
	_estado_ia = EstadoIA.DESMARQUE_OFENSIVO
	_objetivo_desmarque_ofensivo = _calcular_trayectoria_pasa_y_corre(dir_intencion)
	if indicador_control:
		indicador_control.visible = true


## Identifica el espacio libre más cercano hacia la portería rival (área de remate o banda desprotegida),
## trazando una carrera que supera la línea del defensor más cercano y evita el fuera de banda.
func _calcular_trayectoria_pasa_y_corre(dir_intencion: Vector3) -> Vector3:
	var dir_ataque_x: float = 1.0 if equipo == Equipo.LOCAL else -1.0
	var grupo_rivales: String = "equipo_visitante" if equipo == Equipo.LOCAL else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rivales)
	
	# 1. Localizar al defensor rival más cercano para romper su línea defensiva
	var def_mas_cercano: Jugador3D = null
	var min_dist_def: float = 999.0
	for n: Node in rivales:
		var r: Jugador3D = n as Jugador3D
		if r == null or r.posicion_tactica == "PORTERO":
			continue
		var d: float = global_position.distance_to(r.global_position)
		if d < min_dist_def:
			min_dist_def = d
			def_mas_cercano = r
	
	# Superar la línea X del defensor más cercano rumbo a la portería rival
	var x_objetivo: float = global_position.x + dir_ataque_x * 7.8
	if def_mas_cercano != null:
		if equipo == Equipo.LOCAL:
			x_objetivo = maxf(x_objetivo, def_mas_cercano.global_position.x + 2.4)
		else:
			x_objetivo = minf(x_objetivo, def_mas_cercano.global_position.x - 2.4)
	x_objetivo = clampf(x_objetivo, -17.2, 17.2)
	
	# 2. Evaluar carriles candidatos (banda izquierda, centro de remate, banda derecha y dirección del joystick)
	var z_intencion: float = global_position.z + (dir_intencion.z * 4.5 if dir_intencion.length_squared() > 0.04 else 0.0)
	var carriles_z: Array[float] = [
		clampf(z_intencion, -7.8, 7.8),
		clampf(global_position.z, -7.6, 7.6),
		-5.6,
		0.0,
		5.6
	]
	
	var mejor_punto: Vector3 = Vector3(x_objetivo, 0.0, clampf(z_intencion, -7.8, 7.8))
	var mejor_puntaje_espacio: float = -999.0
	
	for z_cand: float in carriles_z:
		var cand: Vector3 = Vector3(x_objetivo, 0.0, clampf(z_cand, -8.2, 8.2))
		var dist_min_rival: float = 99.0
		for n: Node in rivales:
			var r: Jugador3D = n as Jugador3D
			if r == null or r.posicion_tactica == "PORTERO":
				continue
			var d_r: float = cand.distance_to(r.global_position)
			if d_r < dist_min_rival:
				dist_min_rival = d_r
		
		# Evitar amontonarse con otros compañeros
		var dist_min_comp: float = 99.0
		var grupo_amigos: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
		for n_c: Node in get_tree().get_nodes_in_group(grupo_amigos):
			var c: Jugador3D = n_c as Jugador3D
			if c == null or c == self or c.posicion_tactica == "PORTERO":
				continue
			var d_c: float = cand.distance_to(c.global_position)
			if d_c < dist_min_comp:
				dist_min_comp = d_c
		
		var bonus_intencion: float = -abs(z_cand - z_intencion) * 0.25
		var puntaje_espacio: float = dist_min_rival * 1.4 + minf(dist_min_comp, 4.5) * 0.8 + bonus_intencion
		if puntaje_espacio > mejor_puntaje_espacio:
			mejor_puntaje_espacio = puntaje_espacio
			mejor_punto = cand
	
	return mejor_punto


# ==============================================================================
# 4. IA PREDICTIVA DE PASES FILTRADOS (CONOS DE PASE ENTRE LÍNEAS)
# ==============================================================================

## Pase al hueco entre líneas estilo FC Mobile / eFootball:
## 1) Proyecta P_llegada = P_companero + (v_companero * t_trayectoria).
## 2) Lanza múltiples rayos de colisión (PhysicsRayQueryParameters3D) hacia posiciones candidatas en el tercio ofensivo.
## 3) Descarta trayectorias que intersecten con las áreas de intercepción de defensores rivales.
## 4) Ejecuta un impulso físico limpio (apply_central_impulse) con desaceleración orgánica de rodadura, sin frenazos artificiales.
func ejecutar_pase_hueco(potencia: float = 0.5) -> void:
	var b_saque: Balon3D = _obtener_balon_juego()
	var es_saque: bool = (b_saque != null and (b_saque.sacador_autorizado == self or _en_posicion_saque))
	if es_saque:
		_balon_referencia = b_saque
		tiene_posesion = true
		_en_posicion_saque = false
	elif _en_posicion_saque and not tiene_posesion:
		if b_saque != null:
			tomar_posesion(b_saque)
	if not tiene_posesion or _balon_referencia == null:
		return
	
	var era_saque_mano: bool = tiene_balon_en_manos
	var es_pase_pie_campo: bool = (not era_saque_mano and posicion_tactica != "PORTERO")
	var era_controlado_local: bool = (equipo == Equipo.LOCAL and es_controlado and posicion_tactica != "PORTERO")
	var dir_intencion_joystick: Vector3 = _direccion_deseada
	
	var dir_por_defecto: Vector3 = -global_transform.basis.z.normalized()
	if posicion_tactica == "PORTERO":
		dir_por_defecto = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	
	var dir_busqueda: Vector3 = _direccion_deseada if _direccion_deseada.length_squared() > 0.01 else dir_por_defecto
	var companero: Jugador3D = _buscar_mejor_receptor(dir_busqueda)
	
	if companero != null and companero.posicion_tactica != "PORTERO":
		var pos_origen: Vector3 = global_position + Vector3(0.0, 0.25, 0.0) if era_saque_mano else _balon_referencia.global_position
		if era_saque_mano:
			_balon_referencia.global_position = pos_origen
		
		var pos_companero: Vector3 = companero.global_position
		var dist_inicial: float = pos_origen.distance_to(pos_companero)
		var vel_media_pase: float = 10.8 + potencia * 6.5
		var t_trayectoria: float = clampf((dist_inicial / maxf(1.0, vel_media_pase)) + 0.32 + potencia * 0.42, 0.45, 1.30)
		
		# Calcular el punto óptimo mediante Conos de Pase y múltiples PhysicsRayQueryParameters3D
		var p_destino: Vector3 = _calcular_mejor_punto_hueco_conos(pos_origen, companero, t_trayectoria)
		
		var presion: float = calcular_presion_rival()
		var stat_vis: float = gk_saque if era_saque_mano else vision_pase
		var error_total_rad: float = ((99.0 - stat_vis) / 99.0 * 0.08) + (presion * 0.08)
		var desvio_angulo: float = randf_range(-error_total_rad, error_total_rad)
		
		var avance_ofensivo: Vector3 = Vector3(1.0, 0.0, 0.0) if equipo == Equipo.LOCAL else Vector3(-1.0, 0.0, 0.0)
		var vector_hacia_hueco: Vector3 = p_destino - pos_origen
		vector_hacia_hueco.y = 0.0
		var dist_hueco: float = vector_hacia_hueco.length()
		var dir_hueco: Vector3 = vector_hacia_hueco.rotated(Vector3.UP, desvio_angulo).normalized() if dist_hueco > 0.1 else avance_ofensivo
		
		# Impulso limpio y físicamente calculado: el balón llega al hueco rodando a velocidad interceptable (4.5 a 7 m/s)
		var vel_llegada_hueco: float = 4.5 + clampf(potencia, 0.0, 1.0) * 2.5
		var fuerza: float = _balon_referencia.calcular_impulso_rodado(dist_hueco, vel_llegada_hueco)
		
		_en_posicion_saque = false
		if era_saque_mano:
			_t_anim_saque_mano = 0.38
			_estado = EstadoJugador.SAQUE_MANO
		else:
			_t_anim_patada = 0.26
		
		soltar_posesion()
		_t_bloqueo_recaptura = 1.0
		if control_balon_area:
			control_balon_area.set_deferred("monitoring", false)
		_balon_referencia.registrar_pasador(self, 1.0)
		_balon_referencia.liberar_al_hueco(dir_hueco * fuerza + Vector3(0.0, 0.10, 0.0), p_destino, int(equipo), es_pase_pie_campo)
		
		# Si estábamos en saque de centro, notificar inmediatamente al gestor de partido
		var gestor_sc: Node = get_tree().get_first_node_in_group("gestor_partido")
		if gestor_sc and gestor_sc.has_method("notificar_toque_saque_centro"):
			gestor_sc.notificar_toque_saque_centro()
		
		# Activar "Pasa y Corre" en el pasador y ordenar al receptor atacar el hueco filtrado
		if era_controlado_local:
			iniciar_pasa_y_corre(dir_intencion_joystick)
		
		companero.asignar_objetivo_carrera_hueco(p_destino, t_trayectoria + 0.70)
		if equipo == Equipo.LOCAL and es_controlado:
			_transferir_control_a(companero)
	else:
		ejecutar_pase(potencia, TipoPase.RASO)


## Evalúa un abanico de Conos de Pase en el tercio ofensivo lanzando múltiples rayos PhysicsRayQueryParameters3D:
## 1) Calcula P_llegada = P_companero + (v_companero * t_trayectoria).
## 2) Genera puntos candidatos hacia la portería rival (para remate de primera o 1vs1 ante el portero).
## 3) Descarta trayectorias bloqueadas por RayCast3D o dentro del radio de intercepción de defensores rivales.
func _calcular_mejor_punto_hueco_conos(origen: Vector3, companero: Jugador3D, t_trayectoria: float) -> Vector3:
	var dir_ataque_x: float = 1.0 if equipo == Equipo.LOCAL else -1.0
	var avance_ofensivo: Vector3 = Vector3(dir_ataque_x, 0.0, 0.0)
	var pos_arco_rival: Vector3 = Vector3(18.5 * dir_ataque_x, 0.0, 0.0)
	
	# 1. Proyección cinemática del receptor: P_llegada = P_companero + (v_companero * t_trayectoria)
	var vel_sprint_comp: float = (3.85 + (companero.vel_movimiento / 99.0) * 1.75) * 1.22
	var v_comp_plana: Vector3 = Vector3(companero.velocity.x, 0.0, companero.velocity.z)
	var dir_carrera: Vector3 = avance_ofensivo
	if v_comp_plana.length() > 1.0:
		dir_carrera = (v_comp_plana.normalized() * 0.60 + avance_ofensivo * 0.40).normalized()
	var v_companero: Vector3 = dir_carrera * maxf(v_comp_plana.length(), vel_sprint_comp * 0.90)
	
	var p_llegada: Vector3 = companero.global_position + (v_companero * t_trayectoria)
	p_llegada.x = clampf(p_llegada.x, -17.8, 17.8)
	p_llegada.z = clampf(p_llegada.z, -8.4, 8.4)
	p_llegada.y = 0.0
	
	# 2. Construir abanico de candidatos en el tercio ofensivo (hacia el 1v1 con el arquero o zona de remate de primera)
	var hacia_arco_desde_llegada: Vector3 = (pos_arco_rival - p_llegada)
	hacia_arco_desde_llegada.y = 0.0
	var dir_1v1: Vector3 = hacia_arco_desde_llegada.normalized() if hacia_arco_desde_llegada.length() > 0.1 else avance_ofensivo
	
	var candidatos: Array[Vector3] = [
		p_llegada,
		p_llegada + dir_1v1 * 2.2,
		p_llegada + avance_ofensivo * 1.8 + Vector3(0.0, 0.0, -1.6),
		p_llegada + avance_ofensivo * 1.8 + Vector3(0.0, 0.0, 1.6),
		p_llegada + dir_1v1.rotated(Vector3.UP, 0.32) * 2.6,
		p_llegada + dir_1v1.rotated(Vector3.UP, -0.32) * 2.6,
		p_llegada + Vector3(dir_ataque_x * 1.2, 0.0, -signf(p_llegada.z) * 2.4)
	]
	
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var grupo_rivales: String = "equipo_visitante" if equipo == Equipo.LOCAL else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rivales)
	var rids_excluidos: Array[RID] = [get_rid(), companero.get_rid()]
	
	var mejor_candidato: Vector3 = p_llegada
	var mejor_puntaje: float = -9999.0
	
	for cand_raw: Vector3 in candidatos:
		var cand: Vector3 = Vector3(
			clampf(cand_raw.x, -17.8, 17.8),
			0.0,
			clampf(cand_raw.z, -8.4, 8.4)
		)
		var vec_trayectoria: Vector3 = cand - origen
		vec_trayectoria.y = 0.0
		var dist_tray: float = vec_trayectoria.length()
		if dist_tray < 1.2:
			continue
		
		var u_tray: Vector3 = vec_trayectoria / dist_tray
		var normal_lat: Vector3 = Vector3(-u_tray.z, 0.0, u_tray.x)
		var trayectoria_bloqueada: bool = false
		
		# A. Lanzar rayos de colisión (central + márgenes laterales del cono) con PhysicsRayQueryParameters3D
		if space_state != null:
			var offsets_cono: Array[float] = [0.0, -0.42, 0.42]
			for off_lat: float in offsets_cono:
				var despl: Vector3 = normal_lat * off_lat + Vector3(0.0, 0.5, 0.0)
				var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
					origen + despl,
					cand + despl,
					2 # Capa 2: Jugadores
				)
				query.exclude = rids_excluidos
				var hit: Dictionary = space_state.intersect_ray(query)
				if not hit.is_empty() and hit.get("collider") is Jugador3D:
					var col_jug: Jugador3D = hit.get("collider") as Jugador3D
					if col_jug.equipo != equipo and col_jug.posicion_tactica != "PORTERO":
						trayectoria_bloqueada = true
						break
		
		# B. Verificar intersección con áreas de intercepción de los defensores rivales a lo largo del segmento
		var min_holgura_defensor: float = 99.0
		for n: Node in rivales:
			var def_rival: Jugador3D = n as Jugador3D
			if def_rival == null or def_rival.posicion_tactica == "PORTERO":
				continue
			var vec_def: Vector3 = def_rival.global_position - origen
			vec_def.y = 0.0
			var proyeccion_long: float = vec_def.dot(u_tray)
			if proyeccion_long > 0.2 and proyeccion_long < dist_tray + 1.2:
				var punto_mas_cercano: Vector3 = origen + u_tray * clampf(proyeccion_long, 0.0, dist_tray)
				var dist_a_linea: float = Vector2(def_rival.global_position.x - punto_mas_cercano.x, def_rival.global_position.z - punto_mas_cercano.z).length()
				if dist_a_linea < 1.55:
					trayectoria_bloqueada = true
				if dist_a_linea < min_holgura_defensor:
					min_holgura_defensor = dist_a_linea
		
		# C. Puntuar el punto candidato: premiar trayectorias limpias que dejen al receptor en 1vs1 o remate franco
		var dist_al_arco_rival: float = cand.distance_to(pos_arco_rival)
		var dist_carrera_comp: float = companero.global_position.distance_to(cand)
		var penalizacion_bloqueo: float = -45.0 if trayectoria_bloqueada else 0.0
		var bonus_zona_1v1: float = clampf((18.0 - dist_al_arco_rival) * 1.15, 0.0, 16.0)
		var bonus_angulo_remate: float = clampf(4.5 - abs(cand.z) * 0.45, 0.0, 4.5)
		var penalizacion_lejos_comp: float = -maxf(0.0, dist_carrera_comp - 8.5) * 1.6
		
		var puntaje: float = penalizacion_bloqueo + minf(min_holgura_defensor, 5.0) * 2.4 + bonus_zona_1v1 + bonus_angulo_remate + penalizacion_lejos_comp
		if puntaje > mejor_puntaje:
			mejor_puntaje = puntaje
			mejor_candidato = cand
	
	return mejor_candidato


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


## Detecta si una barrida sin tocar balón impacta contra un rival (Falta acumulable de Futsal)
func _chequear_falta_barrida() -> bool:
	var grupo_rivales: String = "equipo_visitante" if equipo == Equipo.LOCAL else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rivales)
	
	for n: Node in rivales:
		var rival: Jugador3D = n as Jugador3D
		if rival == null or rival.posicion_tactica == "PORTERO" or rival.esta_expulsado:
			continue
		var dist: float = global_position.distance_to(rival.global_position)
		if dist < 1.3:
			_barrida_toco_balon = false
			_barrida_cometio_falta = true
			_en_barrida = false
			_tiempo_barrida = 0.0
			_t_aturdimiento = t_cooldown_barrida_fallida
			rival._t_aturdimiento = 0.5
			rival._cooldown_falta_contacto = 1.5
			if rival.tiene_posesion:
				rival.soltar_posesion()
			_notificar_falta_arbitro(self, rival.global_position, rival, true)
			return true
	return false


## Evalúa contacto físico de choque o carga a velocidad alta contra el portador del balón rival
func _chequear_contacto_fisico_falta() -> void:
	if esta_expulsado or tiene_posesion or _en_barrida or _cooldown_falta_contacto > 0.0 or _congelado or _t_aturdimiento > 0.0 or _t_bloqueo_recaptura > 0.0:
		return
	if velocity.length() < 2.8:
		return
	
	for i: int in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		if col == null:
			continue
		var collider: Object = col.get_collider()
		if collider is Jugador3D and collider != self:
			var rival: Jugador3D = collider as Jugador3D
			if rival and rival.equipo != equipo and not rival.esta_expulsado and not rival._en_barrida:
				# Si el rival es el portador del balón, nosotros (defensor en carrera agresiva) somos el infractor
				if rival.tiene_posesion:
					_cooldown_falta_contacto = 1.5
					rival._cooldown_falta_contacto = 1.5
					rival._t_aturdimiento = 0.35
					rival.soltar_posesion()
					_notificar_falta_arbitro(self, rival.global_position, rival, false)
					break


## Notifica al GestorPartido una falta cometida para evaluación de severidad, tarjetas y reanudación
func _notificar_falta_arbitro(infractor: Jugador3D, pos_falta: Vector3, poseedor: Jugador3D = null, es_barrida: bool = false) -> void:
	var gestor: GestorPartido = get_tree().get_first_node_in_group("gestor_partido") as GestorPartido
	if gestor == null and get_parent() != null:
		gestor = get_parent().get_node_or_null("GestorPartido") as GestorPartido
	if gestor != null and gestor.has_method("registrar_falta"):
		gestor.registrar_falta(int(infractor.equipo), pos_falta, infractor, poseedor, es_barrida)


## Ejecuta la sanción de expulsión de la pista (FIFA/IFAB Law 12):
## Retira al futbolista sancionado de la pista, oculta su modelo, anula físicas y colisiones,
## y transfiere inmediatamente el mando táctil a un compañero si era el jugador controlado.
func expulsar_jugador() -> void:
	esta_expulsado = true
	visible = false
	set_physics_process(false)
	set_process(false)
	
	if tiene_posesion:
		soltar_posesion()
	
	for child: Node in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).disabled = true
	if control_balon_area != null:
		control_balon_area.monitoring = false
		control_balon_area.monitorable = false
	
	for hitbox: Area3D in [area_manos, area_pecho, area_piernas, area_cabeza]:
		if hitbox and is_instance_valid(hitbox):
			hitbox.monitoring = false
			hitbox.monitorable = false
	
	var pos_fuera: Vector3 = Vector3(-12.0 if equipo == Equipo.LOCAL else 12.0, 0.0, -11.5)
	global_position = pos_fuera
	velocity = Vector3.ZERO
	
	if is_in_group("jugadores_futsal"):
		remove_from_group("jugadores_futsal")
	var grupo_eq: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
	if is_in_group(grupo_eq):
		remove_from_group(grupo_eq)
	if is_in_group("jugador_activo"):
		remove_from_group("jugador_activo")
	
	if es_controlado:
		es_controlado = false
		_transferir_control_tras_expulsion()


func _transferir_control_tras_expulsion() -> void:
	var grupo_eq: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
	var companeros: Array[Node] = get_tree().get_nodes_in_group(grupo_eq)
	for n: Node in companeros:
		var comp: Jugador3D = n as Jugador3D
		if comp and comp != self and not comp.esta_expulsado and comp.posicion_tactica != "PORTERO":
			comp.es_controlado = true
			comp.add_to_group("jugador_activo")
			var hud: Node = get_tree().get_first_node_in_group("hud_partido")
			if hud and hud.has_method("_actualizar_ficha_jugador_activo"):
				hud.call("_actualizar_ficha_jugador_activo")
			return
	for n: Node in companeros:
		var comp_resto: Jugador3D = n as Jugador3D
		if comp_resto and comp_resto != self and not comp_resto.esta_expulsado:
			comp_resto.es_controlado = true
			comp_resto.add_to_group("jugador_activo")
			return


## Cambia al defensor más cercano al balón o mejor posicionado en la trayectoria de pase/avance rival
func cambiar_a_mas_cercano_al_balon(mostrar_anuncio: bool = true) -> void:
	if equipo != Equipo.LOCAL:
		return
	
	var balon: Balon3D = _obtener_balon_juego()
	var pos_ref: Vector3 = balon.global_position if balon else global_position
	if balon and not balon.esta_siendo_conducido() and balon.linear_velocity.length() > 2.5:
		# Si el balón viaja en un pase, proyectar hacia su trayectoria para elegir al receptor/interceptor ideal
		pos_ref += Vector3(balon.linear_velocity.x, 0.0, balon.linear_velocity.z) * 0.28
	
	var mas_cercano: Jugador3D = obtener_local_mas_cercano(pos_ref, self)
	
	if mas_cercano != null:
		_transferir_control_a(mas_cercano)
		if mostrar_anuncio:
			_emitir_anuncio_hud("CAMBIO DE JUGADOR")


## Ordena presión únicamente al compañero IA más cercano al balón (PRESIÓN 2° DEF)
func ordenar_presion_equipo() -> void:
	var balon: Balon3D = _obtener_balon_juego()
	var pos_ref: Vector3 = balon.global_position if balon else global_position
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var mas_cercano: Jugador3D = null
	var min_d: float = 999.0
	
	for n: Node in locales:
		var jug: Jugador3D = n as Jugador3D
		if jug and not jug.es_controlado and jug.posicion_tactica != "PORTERO":
			jug._orden_presion_equipo = false
			var d: float = jug.global_position.distance_to(pos_ref)
			if d < min_d:
				min_d = d
				mas_cercano = jug
	
	if mas_cercano != null:
		mas_cercano._orden_presion_equipo = true
	_emitir_anuncio_hud("¡PRESIÓN 2° DEFENSOR!")


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
		
		# Bonificación si el compañero está desmarcado o si tiene activa la bandera de prioridad "Pasa y Corre" (es_opcion_de_pase)
		var presion_comp: float = jug.calcular_presion_rival()
		var bonus_desmarque: float = (1.0 - presion_comp) * 0.45
		var bonus_pasa_y_corre: float = 0.90 if jug.es_opcion_de_pase else 0.0
		var puntaje: float = similitud_angulo * 2.2 - (dist * 0.025) + bonus_desmarque + bonus_pasa_y_corre + (vision_pase * 0.005)
		
		if puntaje > mejor_puntaje_fallback:
			mejor_puntaje_fallback = puntaje
			fallback_campo = jug
		
		if (similitud_angulo > 0.05 or jug.es_opcion_de_pase) and puntaje > mejor_puntuacion:
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
# INTELIGENCIA ARTIFICIAL TÁCTICA 5v5 (ZONAL 1-2-1 Y PORTERO DE FÚTSAL REAL)
# ==============================================================================

func _procesar_ia_tactica(delta: float) -> void:
	var nodo_balon: Balon3D = _obtener_balon_juego()
	if nodo_balon == null:
		_direccion_deseada = Vector3.ZERO
		return
	
	var pos_balon: Vector3 = nodo_balon.global_position
	
	# 0. Si este jugador está en pose de barrera, permanecer inmóvil
	if en_pose_barrera:
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false
		return
	
	# 0b. Si este jugador IA es el sacador autorizado en saque (banda, córner, meta, centro, doble penalti)
	if nodo_balon.sacador_autorizado == self or (_en_posicion_saque and tiene_posesion):
		_comportamiento_sacador_ia(pos_balon, nodo_balon)
		return
	
	# 1. IA PORTERO DE FÚTSAL
	if posicion_tactica == "PORTERO":
		_comportamiento_portero(delta, pos_balon, nodo_balon)
		return
	
	var portador: Jugador3D = nodo_balon.portador_actual as Jugador3D if nodo_balon.esta_siendo_conducido() else null
	var rival_tiene_balon: bool = portador != null and portador.equipo == Equipo.VISITANTE
	var local_tiene_balon: bool = portador != null and portador.equipo == Equipo.LOCAL
	
	var gestor_partido: Node = get_tree().get_first_node_in_group("gestor_partido")
	var en_entrenamiento: bool = (gestor_partido != null and ("modo_entrenamiento" in gestor_partido and gestor_partido.modo_entrenamiento))
	
	if en_entrenamiento:
		# En modo entrenamiento ofensivo, el equipo local NUNCA defiende ni repliega; conserva siempre la iniciativa de ataque
		local_tiene_balon = true
		rival_tiene_balon = false
	elif not rival_tiene_balon and not local_tiene_balon:
		if nodo_balon.sacador_autorizado != null:
			local_tiene_balon = (nodo_balon.sacador_autorizado.equipo == Equipo.LOCAL)
			rival_tiene_balon = (nodo_balon.sacador_autorizado.equipo == Equipo.VISITANTE)
		elif nodo_balon.ultimo_toque_equipo == 0:
			# Balón suelto (rebote, desvío, pase en vuelo): el equipo local conserva la iniciativa mientras
			# ningún rival lo controle (ataca el rechace, apoya y se desmarca en vez de replegar).
			local_tiene_balon = true
	
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


## Ejecución reglamentaria de saques por parte de la IA: plantado en su sitio sin huir, apunta a un compañero y pasa (o tira en Doble Penalti)
func _comportamiento_sacador_ia(_pos_balon: Vector3, balon: Balon3D) -> void:
	sprint_activo = false
	if not tiene_posesion and puede_tomar_balon():
		if posicion_tactica == "PORTERO" and _esta_en_area_propia(global_position):
			atrapar_con_manos(balon)
		else:
			tomar_posesion(balon)
		_cooldown_decision_ia = 0.55
	
	var dir_campo: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
	var gestor: Node = get_tree().get_first_node_in_group("gestor_partido")
	var es_doble_penalti: bool = (gestor != null and "estado" in gestor and int(gestor.estado) == 7) # EstadoPartido.DOBLE_PENALTI
	
	if es_doble_penalti:
		_direccion_deseada = dir_campo
		if tiene_posesion and _cooldown_decision_ia <= 0.0:
			ejecutar_tiro(0.78)
		return
	
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


## IA y Técnica Reglamentaria del Portero de Fútsal (sin vuelos de manos de Fútbol 11):
## - Posición de Cruz / "K" (Técnica Canaria) en 1vs1 cuando un delantero rival entra a < 5.0m en el área.
## - Atajadas con Pies y Piernas (Estilo Hockey / Abanico / Espagat) para disparos rasos y cruzados.
## - Bloqueo con Pecho / Rostro para tiros potentes o a quemarropa (rebote en torso rígido sin recepción de manos).
func _comportamiento_portero(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	# Si el portero IA tiene el balón (ESTADO_PORTERO_MANOS), su traslación está bloqueada; rota hacia un compañero y distribuye con la mano
	if tiene_posesion or balon.portador_actual == self:
		_en_achique_cruz_k = false
		sprint_activo = false
		var dir_base_campo: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.0, 0.0)
		var receptor_gk: Jugador3D = _buscar_mejor_receptor(dir_base_campo)
		if receptor_gk != null:
			var hacia_rec: Vector3 = receptor_gk.global_position - global_position
			hacia_rec.y = 0.0
			_direccion_deseada = hacia_rec.normalized() if hacia_rec.length_squared() > 0.01 else dir_base_campo
		else:
			_direccion_deseada = dir_base_campo
		if _cooldown_decision_ia <= 0.0:
			_cooldown_decision_ia = 0.6
			ejecutar_pase(0.55)
		return
	
	var linea_meta_x: float = -19.4 if equipo == Equipo.LOCAL else 19.4
	var dist_al_balon: float = global_position.distance_to(pos_balon)
	var vel_balon: Vector3 = balon.linear_velocity
	var rapidez_tiro: float = vel_balon.length()
	var es_pase_companero: bool = (balon.ultimo_toque_equipo == int(equipo))
	
	var es_tiro_peligroso: bool = false
	if equipo == Equipo.LOCAL and vel_balon.x < -3.6 and pos_balon.x > -19.8:
		es_tiro_peligroso = true
	elif equipo == Equipo.VISITANTE and vel_balon.x > 3.6 and pos_balon.x < 19.8:
		es_tiro_peligroso = true
	
	# Detectar 1vs1 en el área (< 5.0m con balón dominado por delantero rival) -> Posición de Cruz / "K" (Técnica Canaria)
	var portador_rival: Jugador3D = balon.portador_actual as Jugador3D if balon.esta_siendo_conducido() else null
	var rival_en_area: bool = portador_rival != null and portador_rival.equipo != equipo and (_esta_en_area_propia(portador_rival.global_position) or abs(portador_rival.global_position.x - linea_meta_x) < 6.0)
	var es_uno_contra_uno_cruz: bool = rival_en_area and dist_al_balon < 5.0
	_en_achique_cruz_k = es_uno_contra_uno_cruz
	
	# 1. ACHIQUE EN CRUZ / "K" (TÉCNICA CANARIA) EN 1 VS 1 DENTRO DEL ÁREA (< 5 METROS)
	if es_uno_contra_uno_cruz and not es_tiro_peligroso:
		var pos_atacante: Vector3 = portador_rival.global_position
		_lado_atajada = 1.0 if (pos_atacante.z >= global_position.z) else -1.0
		
		# Cerrar ángulo en la bisectriz entre el delantero y el centro del arco manteniendo postura de Cruz / "K"
		var centro_arco: Vector3 = Vector3(linea_meta_x, 0.0, 0.0)
		var dir_bisectriz: Vector3 = (pos_atacante - centro_arco).normalized()
		var avance_achique: float = clampf(dist_al_balon * 0.65, 1.15, 3.8)
		var pos_cruz_k: Vector3 = centro_arco + dir_bisectriz * avance_achique
		pos_cruz_k.z = clampf(pos_cruz_k.z, -1.65, 1.65)
		
		var delta_achique: Vector3 = pos_cruz_k - global_position
		delta_achique.y = 0.0
		_direccion_deseada = delta_achique.normalized() if delta_achique.length() > 0.20 else Vector3.ZERO
		sprint_activo = dist_al_balon > 2.2
		
		# Si el delantero intenta pasar por encima del bloqueo en Cruz a quemarropa (< 1.15m), tapar con pierna/torso
		if dist_al_balon < 1.15 and _tiempo_paradon_reciente <= 0.0 and portador_rival.puede_ser_robado():
			_tiempo_paradon_reciente = 0.95
			var prob_achique: float = clampf((gk_reflejos * 0.55 + gk_posicionamiento * 0.45) / 99.0 * 0.72, 0.25, 0.72)
			if randf() < prob_achique:
				portador_rival.soltar_posesion()
				portador_rival._t_bloqueo_recaptura = 0.55
				var dir_rebote_k: Vector3 = Vector3(1.0 if equipo == Equipo.LOCAL else -1.0, 0.22, _lado_atajada * 0.85).normalized() * 7.8
				balon.patear(dir_rebote_k, int(equipo))
				_emitir_anuncio_hud("¡ACHIQUE EN CRUZ 'K' DE %s!" % nombre_jugador.to_upper())
		return
	
	# 2. ATAJADAS CON PIES/PIERNAS (ESTILO HOCKEY) Y BLOQUEO CON PECHO/ROSTRO EN TIROS A PUERTA
	if es_tiro_peligroso and not es_pase_companero and dist_al_balon < 4.8:
		var limite_cobertura_z: float = 1.20 + (gk_posicionamiento / 99.0) * 0.42
		var intercept_z: float = clampf(pos_balon.z + (vel_balon.z / maxf(0.1, abs(vel_balon.x))) * abs(global_position.x - pos_balon.x), -limite_cobertura_z, limite_cobertura_z)
		var pos_bloqueo: Vector3 = Vector3(global_position.x, 0.0, intercept_z)
		_direccion_deseada = (pos_bloqueo - global_position).normalized()
		sprint_activo = true
		
		var diff_z: float = intercept_z - global_position.z
		var es_tiro_a_quemarropa_o_alto: bool = (pos_balon.y > 0.72) or (rapidez_tiro >= 15.5 and abs(diff_z) < 0.55)
		
		# Activar pose reglamentaria de futsal (Pies estilo Hockey o Bloqueo rígido de Pecho/Rostro; sin vuelos de Fútbol 11)
		if dist_al_balon < 2.8 and _t_anim_atajada <= 0.0:
			_lado_atajada = 1.0 if diff_z >= 0.0 else -1.0
			if es_tiro_a_quemarropa_o_alto:
				# Bloqueo con Pecho / Rostro (torso rígido sin recepción de manos)
				_tipo_atajada_actual = EstadoJugador.ATAJADA_MEDIA
				_t_anim_atajada = 0.46
			else:
				# Atajada con Pies y Piernas (Estilo Hockey / Abanico / Espagat hacia los postes)
				_tipo_atajada_actual = EstadoJugador.ATAJADA_BAJA
				_t_anim_atajada = 0.50
		
		# Alcance físico de desvío con piernas/torso según gk_estirada y gk_reflejos
		var radio_alcance_futsal: float = 0.76 + (gk_estirada / 99.0) * 0.42
		if dist_al_balon < radio_alcance_futsal and _tiempo_paradon_reciente <= 0.0:
			_tiempo_paradon_reciente = 1.0
			
			var factor_potencia_tiro: float = clampf((rapidez_tiro - 11.5) / 18.5, 0.05, 0.98)
			var factor_esquina: float = clampf(abs(pos_balon.z) / 1.80, 0.0, 0.42)
			var dificultad_tiro: float = factor_potencia_tiro * 0.72 + factor_esquina * 0.48
			
			var habilidad_portero: float = ((gk_reflejos * 0.55 + gk_estirada * 0.45) / 99.0) * 0.88
			var prob_atajar: float = clampf(0.50 + (habilidad_portero - dificultad_tiro) * 0.85, 0.14, 0.84)
			
			if randf() < prob_atajar:
				var dist_origen_x: float = abs(pos_balon.x - linea_meta_x)
				# Solo atrapa con las manos si es un balón lento/lejano; en tiros potentes, rasos cruzados o a quemarropa rebota en pies o pecho
				if rapidez_tiro < 11.8 and dist_origen_x > 4.5 and not es_tiro_a_quemarropa_o_alto and abs(diff_z) < 0.45:
					atrapar_con_manos(balon)
					_emitir_anuncio_hud("¡%s SEGURA EL BALÓN!" % nombre_jugador.to_upper())
				elif es_tiro_a_quemarropa_o_alto:
					# Rebote seco contra el torso/pecho rígido sin usar las manos
					var dir_rebote_pecho: Vector3 = Vector3(1.35 if equipo == Equipo.LOCAL else -1.35, 0.32, clampf(diff_z * 1.2, -1.1, 1.1)).normalized()
					var fuerza_rebote_pecho: float = clampf(rapidez_tiro * 0.58, 7.5, 12.5)
					balon.patear(dir_rebote_pecho * fuerza_rebote_pecho, int(equipo))
					_emitir_anuncio_hud("¡BLOQUEO DE PECHO DE %s!" % nombre_jugador.to_upper())
				else:
					# Desvío lateral hacia el costado con el pie/pierna en abanico (estilo hockey)
					var dir_pie_z: float = 1.0 if pos_balon.z >= 0.0 else -1.0
					var impulso_pie: Vector3 = Vector3(1.10 if equipo == Equipo.LOCAL else -1.10, 0.24, dir_pie_z * 1.55).normalized() * 8.6
					balon.patear(impulso_pie, int(equipo))
					_emitir_anuncio_hud("¡ATAJADA CON EL PIE DE %s!" % nombre_jugador.to_upper())
		return
	
	# 3. RECEPCIÓN DE PASE ATRÁS (CESIÓN CON EL PIE) O BALÓN SUELTO EN EL ÁREA
	var dentro_area_propia: bool = _esta_en_area_propia(pos_balon)
	if not balon.esta_siendo_conducido() and balon.sacador_autorizado == null and (dentro_area_propia or (es_pase_companero and dist_al_balon < 6.0 and abs(pos_balon.x - linea_meta_x) < 8.0)):
		_direccion_deseada = (pos_balon - global_position).normalized()
		sprint_activo = dist_al_balon > 1.5
		if dist_al_balon < 1.05 and puede_tomar_balon():
			Portero.procesar_recepcion(self, balon)
		return
	
	# 4. POSICIONAMIENTO ANGULAR EN ARCO (IDLE_ARQUERO)
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


## Retorna el ancla posicional relativa del sistema táctico 1-2-1 de Futsal (1 Cierre, 2 Alas, 1 Pívot)
func _obtener_ancla_zonal_rol(pos_balon: Vector3, es_equipo_local: bool, en_ataque: bool) -> Vector3:
	var dir_ataque: float = 1.0 if es_equipo_local else -1.0
	var x_base_def: float = -11.5 if es_equipo_local else 11.5
	
	if en_ataque:
		match posicion_tactica:
			"CIERRE":
				# 1 Cierre: equilibrio táctico detrás de la línea del balón ofreciendo pase de seguridad
				var x_cie: float = clampf(pos_balon.x - dir_ataque * 6.0, -14.5, 14.5)
				var z_cie: float = clampf(pos_balon.z * 0.30, -3.2, 3.2)
				return Vector3(x_cie, 0.0, z_cie)
			"ALA_IZQ":
				# Ala Izquierda: amplitud en banda izquierda (Z negativa) manteniendo línea de pase abierta
				var x_ai: float = clampf(pos_balon.x + dir_ataque * 3.8, -15.5, 15.8)
				var z_ai: float = -6.4 if abs(pos_balon.x) < 11.5 else -4.8
				return Vector3(x_ai, 0.0, z_ai)
			"ALA_DER":
				# Ala Derecha: amplitud en banda derecha (Z positiva) manteniendo línea de pase abierta
				var x_ad: float = clampf(pos_balon.x + dir_ataque * 3.8, -15.5, 15.8)
				var z_ad: float = 6.4 if abs(pos_balon.x) < 11.5 else 4.8
				return Vector3(x_ad, 0.0, z_ad)
			"PIVOT":
				# 1 Pívot: referencia ofensiva profunda entre central y segundo palo
				var x_piv: float = clampf(pos_balon.x + dir_ataque * 7.2, -16.2, 16.2)
				var z_piv: float = clampf(-pos_balon.z * 0.45, -3.6, 3.6)
				return Vector3(x_piv, 0.0, z_piv)
	else:
		# Anclas defensivas zonales 1-2-1 para proteger carriles sin amontonarse
		var despl_x: float = clampf(pos_balon.x * 0.38, -5.5, 5.5)
		match posicion_tactica:
			"CIERRE":
				var x_c_def: float = clampf(x_base_def + despl_x - dir_ataque * 2.2, -16.2, 16.2)
				var z_c_def: float = clampf(pos_balon.z * 0.35, -3.2, 3.2)
				return Vector3(x_c_def, 0.0, z_c_def)
			"ALA_IZQ":
				var x_ai_def: float = clampf(x_base_def + despl_x + dir_ataque * 2.0, -14.5, 14.5)
				var z_ai_def: float = clampf(-5.0 + minf(0.0, pos_balon.z * 0.25), -7.4, -2.6)
				return Vector3(x_ai_def, 0.0, z_ai_def)
			"ALA_DER":
				var x_ad_def: float = clampf(x_base_def + despl_x + dir_ataque * 2.0, -14.5, 14.5)
				var z_ad_def: float = clampf(5.0 + maxf(0.0, pos_balon.z * 0.25), 2.6, 7.4)
				return Vector3(x_ad_def, 0.0, z_ad_def)
			"PIVOT":
				var x_p_def: float = clampf(pos_balon.x - dir_ataque * 2.5, -8.5, 8.5)
				var z_p_def: float = clampf(pos_balon.z * 0.25, -3.0, 3.0)
				return Vector3(x_p_def, 0.0, z_p_def)
	
	return _posicion_tactica_inicial


## Aplica un radio de dispersión mínimo obligatorio (>= 2.5m) respecto a todos los compañeros de equipo
func _aplicar_dispersion_companeros(pos_objetivo: Vector3) -> Vector3:
	var grupo_propio: String = "equipo_local" if equipo == Equipo.LOCAL else "equipo_visitante"
	var companeros: Array[Node] = get_tree().get_nodes_in_group(grupo_propio)
	var pos_ajustada: Vector3 = pos_objetivo
	var radio_min_comp: float = maxf(2.65, radio_dispersion_companeros)
	
	for n: Node in companeros:
		var comp: Jugador3D = n as Jugador3D
		if comp == null or comp == self or comp.posicion_tactica == "PORTERO":
			continue
		var diff: Vector3 = pos_ajustada - comp.global_position
		diff.y = 0.0
		var dist: float = diff.length()
		if dist < radio_min_comp:
			var dir_alejamiento: Vector3 = diff.normalized() if dist > 0.05 else (_posicion_tactica_inicial - comp.global_position).normalized()
			if dir_alejamiento.length_squared() < 0.01:
				dir_alejamiento = Vector3(0.0, 0.0, -1.0 if posicion_tactica == "ALA_IZQ" else 1.0)
			pos_ajustada = comp.global_position + dir_alejamiento * radio_min_comp
	
	pos_ajustada.x = clampf(pos_ajustada.x, -17.5, 17.5)
	pos_ajustada.z = clampf(pos_ajustada.z, -8.6, 8.6)
	pos_ajustada.y = 0.0
	return pos_ajustada


## Calcula la posición de desmarque dinámico en estructura 1-2-1 respetando radio de dispersión >= 2.5m,
## desmarques a la espalda de la barrera y apertura de líneas de pase en tiros libres
func _calcular_posicion_desmarque_ofensivo(pos_balon: Vector3, es_equipo_local: bool) -> Vector3:
	var pos_objetivo: Vector3 = _obtener_ancla_zonal_rol(pos_balon, es_equipo_local, true)
	var grupo_rivales: String = "equipo_visitante" if es_equipo_local else "equipo_local"
	var rivales: Array[Node] = get_tree().get_nodes_in_group(grupo_rivales)
	
	# Detectar si hay barrera defensiva activa (Tiro Libre / Falta)
	var defensores_barrera: Array[Jugador3D] = []
	for n: Node in rivales:
		var def_r: Jugador3D = n as Jugador3D
		if def_r and def_r.en_pose_barrera:
			defensores_barrera.append(def_r)
	
	if not defensores_barrera.is_empty():
		var pos_centro_barrera: Vector3 = Vector3.ZERO
		for db: Jugador3D in defensores_barrera:
			pos_centro_barrera += db.global_position
		pos_centro_barrera /= float(defensores_barrera.size())
		pos_centro_barrera.y = 0.0
		
		var t_futsal: float = float(Time.get_ticks_msec()) * 0.001
		
		# A. Companero_Frontal (ALA_IZQ / PIVOT): Desmarque a la espalda de la barrera / segundo palo
		if posicion_tactica == "ALA_IZQ" or posicion_tactica == "PIVOT":
			var osc_x: float = sin(t_futsal * 1.8) * 1.4
			var osc_z: float = cos(t_futsal * 1.5) * 1.2
			var x_tras_barrera: float = clampf(pos_centro_barrera.x + 1.6 + osc_x, pos_centro_barrera.x + 0.6, 17.6)
			var z_segundo_palo: float = clampf(-signf(pos_balon.z if abs(pos_balon.z) > 0.2 else 1.0) * 4.2 + osc_z, -6.5, 6.5)
			pos_objetivo = Vector3(x_tras_barrera, 0.0, z_segundo_palo)
		
		# B. Companero_Banda (ALA_DER): Amplitud, basculación y desdoble por la banda abierta
		elif posicion_tactica == "ALA_DER":
			var osc_x_b: float = sin(t_futsal * 1.5 + 0.6) * 1.6
			var osc_z_b: float = cos(t_futsal * 1.2) * 0.8
			var z_abierta: float = 6.4 if pos_balon.z < 0.0 else -6.4
			var x_abierta: float = clampf(pos_balon.x + 3.8 + osc_x_b, pos_balon.x + 1.8, 16.8)
			pos_objetivo = Vector3(x_abierta, 0.0, clampf(z_abierta + osc_z_b, -8.4, 8.4))
		
		# C. Desdoble para mantener la línea de pase limpia hacia el lanzador
		var vec_trayectoria: Vector3 = pos_objetivo - pos_balon
		vec_trayectoria.y = 0.0
		var dist_tray: float = vec_trayectoria.length()
		if dist_tray > 0.5:
			var dir_tray: Vector3 = vec_trayectoria / dist_tray
			for db: Jugador3D in defensores_barrera:
				var v_def: Vector3 = db.global_position - pos_balon
				v_def.y = 0.0
				var proy: float = v_def.dot(dir_tray)
				if proy > 0.5 and proy < dist_tray:
					var p_cercano: Vector3 = pos_balon + dir_tray * proy
					var dist_bloqueo: float = (db.global_position - p_cercano).length()
					if dist_bloqueo < 1.4:
						var perp_out: float = 1.6 if pos_objetivo.z >= pos_centro_barrera.z else -1.6
						pos_objetivo.z = clampf(pos_objetivo.z + perp_out, -8.6, 8.6)
						break
	else:
		# Desmarque activo en juego abierto: desplazarse fuera de la marca del defensor más cercano
		var offset_desmarque: Vector3 = Vector3.ZERO
		for n: Node in rivales:
			var def_rival: Jugador3D = n as Jugador3D
			if def_rival and def_rival.posicion_tactica != "PORTERO":
				var diff_r: Vector3 = pos_objetivo - def_rival.global_position
				diff_r.y = 0.0
				var d_r: float = diff_r.length()
				if d_r < 3.0 and d_r > 0.01:
					offset_desmarque += diff_r.normalized() * ((3.0 - d_r) / 3.0) * 1.85
		pos_objetivo += offset_desmarque

	return _aplicar_dispersion_companeros(pos_objetivo)


## Apoyo ofensivo y desmarque del equipo visitante (CPU en ataque)
func _comportamiento_apoyo_ofensivo_rival(pos_balon: Vector3, _balon: Balon3D) -> void:
	if _t_desmarque_ofensivo > 0.0:
		_estado_ia = EstadoIA.DESMARQUE_OFENSIVO
		es_opcion_de_pase = true
		var delta_run: Vector3 = _objetivo_desmarque_ofensivo - global_position
		delta_run.y = 0.0
		if delta_run.length() > 0.35:
			_direccion_deseada = delta_run.normalized()
			sprint_activo = true
		else:
			_direccion_deseada = Vector3(-1.0, 0.0, 0.0)
			sprint_activo = false
		return
	
	_estado_ia = EstadoIA.DESMARQUE_APOYO
	var pos_objetivo: Vector3 = _objetivo_carrera_hueco if _t_carrera_hueco > 0.0 else _calcular_posicion_desmarque_ofensivo(pos_balon, false)
	
	var delta_pos: Vector3 = pos_objetivo - global_position
	delta_pos.y = 0.0
	if delta_pos.length() > 0.45:
		_direccion_deseada = delta_pos.normalized()
		sprint_activo = (_t_carrera_hueco > 0.0) or (delta_pos.length() > 2.4)
	else:
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false


## Retorna true si este jugador local IA es el más cercano de todo el equipo a un balón suelto sin sacador
## (excluye al arquero y respeta al jugador humano: si el usuario está más cerca, la IA no le roba el rechace)
func _debe_perseguir_balon_suelto_local(pos_balon: Vector3, balon: Balon3D) -> bool:
	if balon == null or balon.esta_siendo_conducido() or balon.sacador_autorizado != null:
		return false
	if es_controlado or posicion_tactica == "PORTERO" or en_pose_barrera or _en_posicion_saque:
		return false
	var mas_cercano: Jugador3D = obtener_local_mas_cercano(pos_balon)
	return mas_cercano == self


## Retorna el jugador local de campo (sin arquero ni expulsados) más cercano a una posición del mundo
func obtener_local_mas_cercano(pos: Vector3, excluir: Jugador3D = null) -> Jugador3D:
	var mejor: Jugador3D = null
	var min_d: float = INF
	for n: Node in get_tree().get_nodes_in_group("equipo_local"):
		var j: Jugador3D = n as Jugador3D
		if j == null or j == excluir or j.posicion_tactica == "PORTERO" or j.esta_expulsado:
			continue
		var d: float = j.global_position.distance_to(pos)
		if d < min_d:
			min_d = d
			mejor = j
	return mejor


## Ataque y desmarque inteligente de compañeros del equipo local (incluyendo Mecánica "Pasa y Corre" / Give-and-Go)
func _comportamiento_ataque_local(pos_balon: Vector3, _balon: Balon3D) -> void:
	# Mecánica "Pasa y Corre" (DESMARQUE_OFENSIVO durante 2.0 a 3.0 segundos tras soltar un pase):
	# El pasador no frena ni vuelve a su ancla pasiva; rompe la línea defensiva hacia el espacio libre
	# manteniendo es_opcion_de_pase = true con prioridad alta para cámara y asistencia de pase.
	if _t_desmarque_ofensivo > 0.0:
		_estado_ia = EstadoIA.DESMARQUE_OFENSIVO
		es_opcion_de_pase = true
		var pos_meta_run: Vector3 = _objetivo_carrera_hueco if _t_carrera_hueco > 0.0 else _objetivo_desmarque_ofensivo
		var delta_run: Vector3 = pos_meta_run - global_position
		delta_run.y = 0.0
		if delta_run.length() > 0.38:
			_direccion_deseada = delta_run.normalized()
			sprint_activo = true
		else:
			# Si alcanza el primer punto antes de que termine el temporizador, perfilarse hacia el arco rival sin regresar al ancla
			var hacia_arco_rival: Vector3 = Vector3(17.2, 0.0, clampf(global_position.z * 0.7, -5.5, 5.5)) - global_position
			hacia_arco_rival.y = 0.0
			_direccion_deseada = hacia_arco_rival.normalized() if hacia_arco_rival.length() > 0.6 else Vector3.ZERO
			sprint_activo = hacia_arco_rival.length() > 0.6
		return
	
	_estado_ia = EstadoIA.DESMARQUE_APOYO
	es_opcion_de_pase = true
	
	# Balón suelto propio (rebote tras tiro/pase): el jugador local IA más cercano persigue el rechace
	# (mismo criterio que la defensa local: solo si ningún humano controlado está más cerca)
	if _debe_perseguir_balon_suelto_local(pos_balon, _balon):
		_estado_ia = EstadoIA.PRESIÓN
		var hacia_rechace: Vector3 = pos_balon - global_position
		hacia_rechace.y = 0.0
		_direccion_deseada = hacia_rechace.normalized() if hacia_rechace.length_squared() > 0.01 else Vector3.ZERO
		sprint_activo = true
		return
	
	var pos_desmarque: Vector3 = _objetivo_carrera_hueco if _t_carrera_hueco > 0.0 else _calcular_posicion_desmarque_ofensivo(pos_balon, true)
	
	var gestor_atq: Node = get_tree().get_first_node_in_group("gestor_partido")
	var es_entrenamiento_atq: bool = (gestor_atq != null and ("modo_entrenamiento" in gestor_atq and gestor_atq.modo_entrenamiento))
	if es_entrenamiento_atq:
		# En modo entrenamiento ofensivo, mantener a los compañeros siempre en tres cuartos y área rival (> 3.5m)
		pos_desmarque.x = clampf(pos_desmarque.x, 3.5, 17.5)
	
	var delta_desmarque: Vector3 = pos_desmarque - global_position
	delta_desmarque.y = 0.0
	var dist_desmarque: float = delta_desmarque.length()
	if dist_desmarque > 0.45:
		_direccion_deseada = delta_desmarque.normalized()
		sprint_activo = (_t_carrera_hueco > 0.0) or (dist_desmarque > 2.4)
	else:
		_direccion_deseada = delta_desmarque.normalized() * 0.35 if dist_desmarque > 0.08 else Vector3.ZERO
		sprint_activo = false


## Calcula la posición de cobertura defensiva combinando el ancla zonal 1-2-1, vigilancia de línea de pase y dispersión >= 2.5m
func _calcular_posicion_marcaje_defensivo(pos_balon: Vector3, es_equipo_local: bool) -> Vector3:
	var ancla_zonal: Vector3 = _obtener_ancla_zonal_rol(pos_balon, es_equipo_local, false)
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
	for n: Node in atacantes:
		var atq: Jugador3D = n as Jugador3D
		if atq == null or atq.posicion_tactica == "PORTERO" or atq.tiene_posesion:
			continue
		if atq.posicion_tactica == rol_objetivo:
			atacante_asignado = atq
			break
	
	var pos_objetivo: Vector3 = ancla_zonal
	if atacante_asignado != null:
		var pos_atq: Vector3 = atacante_asignado.global_position
		var dir_arco: Vector3 = (arco_propio - pos_atq).normalized()
		var dir_balon: Vector3 = (pos_balon - pos_atq).normalized()
		var pos_linea_pase: Vector3 = pos_atq + (dir_arco * 1.65 + dir_balon * 0.65)
		# Ponderar 55% ancla zonal 1-2-1 y 45% corte de línea de pase para evitar ser arrastrados al mismo punto
		pos_objetivo = ancla_zonal.lerp(pos_linea_pase, 0.45)
	
	return _aplicar_dispersion_companeros(pos_objetivo)


## Defensa táctica 1-2-1 del equipo visitante:
## SOLO el jugador más cercano al balón presiona directamente; los otros 3 mantienen coberturas zonales y líneas de pase (>= 2.5m)
func _comportamiento_defensa_rival(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	if _t_desmarque_ofensivo > 0.0:
		_t_desmarque_ofensivo = 0.0
		es_opcion_de_pase = false
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
	
	# CASO A: Balón libre en juego -> ÚNICAMENTE el jugador más cercano va por el balón; el resto mantiene su zona
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
	
	# CASO B: El equipo local conduce el balón -> si el portador está en saque reglamentario, mantener distancia y zona
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


## Defensa táctica 1-2-1 de compañeros del equipo local:
## Evita el "Efecto Enjambre": si el jugador controlado ya es el más cercano o ningún compañero tiene orden de presión,
## los compañeros IA mantienen sus anclas zonales (Cierre, Alas, Pívot) con dispersión mínima de 2.5m.
func _comportamiento_defensa_local(_delta: float, pos_balon: Vector3, balon: Balon3D) -> void:
	if _t_desmarque_ofensivo > 0.0:
		_t_desmarque_ofensivo = 0.0
		es_opcion_de_pase = false
	var dist_balon: float = global_position.distance_to(pos_balon)
	
	# Si el rival está ejecutando un saque reglamentario, no invadir ni perseguir hasta que el balón se juegue
	var portador_actual: Jugador3D = balon.portador_actual as Jugador3D if balon.esta_siendo_conducido() else null
	var rival_es_sacador: bool = (balon.sacador_autorizado != null and balon.sacador_autorizado.equipo == Equipo.VISITANTE) or (portador_actual != null and portador_actual.equipo == Equipo.VISITANTE and portador_actual._en_posicion_saque)
	if rival_es_sacador:
		_direccion_deseada = Vector3.ZERO
		sprint_activo = false
		return
	
	var locales: Array[Node] = get_tree().get_nodes_in_group("equipo_local")
	var absoluto_mas_cercano: Jugador3D = null
	var min_d_abs: float = 999.0
	for n: Node in locales:
		var j_loc: Jugador3D = n as Jugador3D
		if j_loc and j_loc.posicion_tactica != "PORTERO":
			var d: float = j_loc.global_position.distance_to(pos_balon)
			if d < min_d_abs:
				min_d_abs = d
				absoluto_mas_cercano = j_loc
	
	# Solo presiona directamente si este compañero IA es el jugador más cercano de todo el equipo al balón suelto,
	# o si recibió la orden explícita de presión secundaria
	var debe_ir_al_balon: bool = _orden_presion_equipo or (not balon.esta_siendo_conducido() and balon.sacador_autorizado == null and absoluto_mas_cercano == self)
	
	if debe_ir_al_balon:
		_estado_ia = EstadoIA.PRESIÓN
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
		_estado_ia = EstadoIA.COBERTURA
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


## Calcula la repulsión antipenetración y mantiene el radio de dispersión mínimo de 2.5m entre compañeros
func _calcular_separacion() -> Vector3:
	if es_controlado or _en_posicion_saque or tiene_balon_en_manos:
		return Vector3.ZERO
	
	var empuje: Vector3 = Vector3.ZERO
	var todos_jugadores: Array[Node] = get_tree().get_nodes_in_group("jugadores_futsal")
	
	for nodo: Node in todos_jugadores:
		if nodo == self or not (nodo is Jugador3D):
			continue
		var otro: Jugador3D = nodo as Jugador3D
		if otro.posicion_tactica == "PORTERO":
			continue
		var diff: Vector3 = global_position - otro.global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d <= 0.0001:
			continue
		
		# Entre compañeros del mismo equipo aplicamos el radio de dispersión táctico (>= 2.5 metros)
		var es_companero: bool = (otro.equipo == equipo)
		var radio_objetivo: float = radio_dispersion_companeros if es_companero else radio_separacion
		
		if d < radio_objetivo:
			var peso: float = 1.15 if (es_companero or otro.es_controlado) else 0.55
			var magnitud: float = ((radio_objetivo - d) / radio_objetivo) * fuerza_separacion * peso
			empuje += diff.normalized() * magnitud
	
	return empuje


func _aplicar_movimiento(delta: float) -> void:
	# 1. BLOQUEO TOTAL DE TRASLACIÓN DEL PORTERO CON BALÓN EN MANOS (SOLUCIÓN AL AUTOGOL ILÓGICO):
	# Cuando el arquero tiene el balón en manos, velocity = Vector3.ZERO y el joystick SOLO rota su orientación visual.
	if tiene_balon_en_manos or _estado == EstadoJugador.ESTADO_PORTERO_MANOS:
		velocity = Vector3.ZERO
		var dir_campo_x: float = 1.0 if equipo == Equipo.LOCAL else -1.0
		var angulo_base_campo: float = atan2(-dir_campo_x, 0.0)
		if _direccion_deseada.length_squared() > 0.01:
			# Permitir rotar a izquierda/derecha hacia la cancha sin girar nunca hacia adentro de su propio arco
			var dir_apuntado: Vector3 = _direccion_deseada
			if equipo == Equipo.LOCAL:
				dir_apuntado.x = maxf(0.25, dir_apuntado.x)
			else:
				dir_apuntado.x = minf(-0.25, dir_apuntado.x)
			dir_apuntado = dir_apuntado.normalized()
			var angulo_apuntado_gk: float = atan2(-dir_apuntado.x, -dir_apuntado.z)
			rotation.y = lerp_angle(rotation.y, angulo_apuntado_gk, clampf(velocidad_giro * delta, 0.0, 1.0))
		else:
			rotation.y = lerp_angle(rotation.y, angulo_base_campo, clampf(8.0 * delta, 0.0, 1.0))
		return
	
	# 2. BLOQUEO DE TRASLACIÓN EN SAQUE DE CENTRO Y REANUDACIONES DETENIDAS:
	# El sacador no puede caminar ni conducir; el joystick solo rota al jugador para apuntar el pase obligatorio.
	if _en_posicion_saque:
		global_position = _pos_anclaje_saque
		velocity = Vector3.ZERO
		var gestor_saque: Node = get_tree().get_first_node_in_group("gestor_partido")
		var es_entrenamiento_saque: bool = (gestor_saque != null and ("modo_entrenamiento" in gestor_saque and gestor_saque.modo_entrenamiento))
		if not es_entrenamiento_saque and _direccion_deseada.length_squared() > 0.01:
			var angulo_apuntado: float = atan2(-_direccion_deseada.x, -_direccion_deseada.z)
			rotation.y = lerp_angle(rotation.y, angulo_apuntado, clampf(velocidad_giro * delta, 0.0, 1.0))
		return
	
	# Velocidad calibrada para un ritmo de partido táctico, realista y totalmente controlable
	var vel_base: float = 3.85 + (vel_movimiento / 99.0) * 1.75
	var acel_base: float = 26.0 + (vel_movimiento / 99.0) * 10.0
	var vel_max_efectiva: float = vel_base * (1.22 if sprint_activo else 1.0)
	
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
		if (es_opcion_de_pase or _estado_ia == EstadoIA.DESMARQUE_APOYO) and not es_controlado:
			var nodo_b: Balon3D = _obtener_balon_juego()
			if nodo_b != null and is_instance_valid(nodo_b):
				var dir_b: Vector3 = nodo_b.global_position - global_position
				dir_b.y = 0.0
				if dir_b.length_squared() > 0.04:
					var ang_b: float = atan2(-dir_b.x, -dir_b.z)
					rotation.y = lerp_angle(rotation.y, ang_b, clampf(velocidad_giro * delta, 0.0, 1.0))
	
	var empuje_sep: Vector3 = _calcular_separacion()
	vel_horizontal += empuje_sep
	
	var vel_max_clamp: float = vel_max_efectiva * 1.08
	if vel_horizontal.length() > vel_max_clamp:
		vel_horizontal = vel_horizontal.normalized() * vel_max_clamp
	
	velocity.x = vel_horizontal.x
	velocity.z = vel_horizontal.z


## Animación procedural de extremidades con técnica real de Portero de Fútsal:
## - ACHIQUE_CRUZ_K: Posición de Cruz / "K" (Técnica Canaria) en 1vs1 (pierna extendida lateral, rodilla opuesta en tierra bloqueando caño, torso erguido y brazos abiertos).
## - ATAJADA_BAJA: Atajada con pies y piernas estilo Hockey (abanico/espagat proyectando el pie hacia el poste, sin vuelo de manos).
## - ATAJADA_MEDIA: Bloqueo de pecho / rostro con torso rígido sin recepción de manos.
## - ESTADO_PORTERO_MANOS / SAQUE_MANO: Posesión fija en manos con rotación de apuntado y lanzamiento manual.
func _animar_extremidades(delta: float) -> void:
	var tiene_pivotes_legacy: bool = (
		pivote_pierna_izq != null
		and pivote_pierna_der != null
		and pivote_brazo_izq != null
		and pivote_brazo_der != null
	)
	if not tiene_pivotes_legacy and esqueleto_humanoide == null:
		return

	var vel_plana: float = Vector2(velocity.x, velocity.z).length()

	# ==========================================================================
	# A. ANIMACIONES REGLAMENTARIAS DEL PORTERO DE FÚTSAL
	# ==========================================================================
	if posicion_tactica == "PORTERO" and _estado != EstadoJugador.ENTRADA:
		# Si NO tiene el balón en las manos, orientar la mirada hacia la cancha;
		# si tiene el balón en las manos (ESTADO_PORTERO_MANOS), respetar la rotación del joystick calculada en _aplicar_movimiento
		if not tiene_balon_en_manos and _estado != EstadoJugador.ESTADO_PORTERO_MANOS:
			var arco_mirada_x: float = 1.0 if equipo == Equipo.LOCAL else -1.0
			rotation.y = lerp_angle(rotation.y, atan2(-arco_mirada_x, 0.0), clampf(10.0 * delta, 0.0, 1.0))

		# 1. Estado SAQUE_MANO (lanzamiento manual con el brazo para saques de meta y distribución rápida)
		if _estado == EstadoJugador.SAQUE_MANO or _t_anim_saque_mano > 0.0:
			var progreso_saque: float = 1.0 - clampf(_t_anim_saque_mano / 0.38, 0.0, 1.0)
			var arco_brazo: float = sin(progreso_saque * PI)
			_ang_brazo_der_x = lerpf(-0.95, 1.65, progreso_saque)
			_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.25, delta * 15.0)
			_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.45 - arco_brazo * 0.5, delta * 15.0)
			_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.25, delta * 15.0)
			_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.48 * arco_brazo, delta * 15.0)
			_ang_pierna_der_x = lerpf(_ang_pierna_der_x, -0.38 * arco_brazo, delta * 15.0)
			_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.0, delta * 15.0)
			_ang_pierna_der_z = lerpf(_ang_pierna_der_z, 0.0, delta * 15.0)
			_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.25 * arco_brazo, delta * 15.0)
			_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.35 * arco_brazo, delta * 15.0)
			if visual:
				visual.rotation.x = lerpf(visual.rotation.x, -0.18 * arco_brazo, delta * 15.0)
				visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 15.0)
				visual.position.y = lerpf(visual.position.y, 0.0, delta * 15.0)
			_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
			return

		# 2. Estado ACHIQUE_CRUZ_K: Posición de Cruz / "K" (Técnica Canaria) en 1vs1 (< 5m en el área)
		if _estado == EstadoJugador.ACHIQUE_CRUZ_K or _en_achique_cruz_k:
			var extiende_izq: bool = (_lado_atajada >= 0.0)
			if extiende_izq:
				# Pierna izquierda extendida hacia el costado y rodilla derecha en el suelo bloqueando el túnel entrepiernas
				_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.18, delta * 18.0)
				_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 1.08, delta * 18.0)
				_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.96, delta * 18.0)
				_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -0.22, delta * 18.0)
				_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.10, delta * 18.0)
				_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -1.15, delta * 18.0)
			else:
				# Pierna derecha extendida hacia el costado y rodilla izquierda en el suelo bloqueando el túnel entrepiernas
				_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.18, delta * 18.0)
				_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -1.08, delta * 18.0)
				_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.96, delta * 18.0)
				_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.22, delta * 18.0)
				_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.10, delta * 18.0)
				_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -1.15, delta * 18.0)

			# Torso recto erguido y brazos abiertos en cruz cubriendo ángulos altos y medios
			_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.35, delta * 18.0)
			_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.35, delta * 18.0)
			_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.96, delta * 18.0)
			_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.96, delta * 18.0)
			if visual:
				visual.rotation.x = lerpf(visual.rotation.x, -0.03, delta * 18.0)
				visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 18.0)
				visual.position.y = lerpf(visual.position.y, -0.32, delta * 18.0)
			_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
			return

		# 3. Estados ATAJADA_BAJA (Pies/Piernas Estilo Hockey - Abanico/Espagat) y ATAJADA_MEDIA (Bloqueo Pecho/Rostro)
		if _estado == EstadoJugador.ATAJADA_BAJA or _estado == EstadoJugador.ATAJADA_MEDIA or _t_anim_atajada > 0.0:
			if _estado == EstadoJugador.ATAJADA_MEDIA or _tipo_atajada_actual == EstadoJugador.ATAJADA_MEDIA:
				# Bloqueo con Pecho / Rostro: torso rígido frontal, brazos abiertos/atrás protegiendo sin recepción de manos
				_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.18, delta * 18.0)
				_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.18, delta * 18.0)
				_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.68, delta * 18.0)
				_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.68, delta * 18.0)
				_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.28, delta * 18.0)
				_ang_pierna_der_x = lerpf(_ang_pierna_der_x, -0.22, delta * 18.0)
				_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.32, delta * 18.0)
				_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -0.32, delta * 18.0)
				_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.25, delta * 18.0)
				_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.25, delta * 18.0)
				if visual:
					visual.rotation.x = lerpf(visual.rotation.x, -0.05, delta * 18.0)
					visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 18.0)
					visual.position.y = lerpf(visual.position.y, -0.06, delta * 18.0)
			else:
				# Atajada con Pies y Piernas (Estilo Hockey / Espagat proyectando el pie hacia el poste, sin lanzarse de manos)
				var proyecta_izq: bool = (_lado_atajada >= 0.0)
				if proyecta_izq:
					_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.42, delta * 20.0)
					_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 1.25, delta * 20.0)
					_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.72, delta * 20.0)
					_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -0.38, delta * 20.0)
					_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.08, delta * 20.0)
					_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.85, delta * 20.0)
				else:
					_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.42, delta * 20.0)
					_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -1.25, delta * 20.0)
					_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.72, delta * 20.0)
					_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.38, delta * 20.0)
					_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.08, delta * 20.0)
					_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.85, delta * 20.0)

				# Brazos equilibrando a media altura (sin estirarse hacia el suelo como en Fútbol 11)
				_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.40, delta * 18.0)
				_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.40, delta * 18.0)
				_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.78, delta * 18.0)
				_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.78, delta * 18.0)
				if visual:
					visual.rotation.x = lerpf(visual.rotation.x, -0.06, delta * 16.0)
					visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 16.0)
					visual.position.y = lerpf(visual.position.y, -0.28, delta * 18.0)
			_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
			return

		# 4. Estado IDLE_ARQUERO y ESTADO_PORTERO_MANOS
		_fase_carrera = fmod(_fase_carrera + delta * (4.2 + vel_plana * 1.8), TAU)
		var balanceo_lat: float = sin(_fase_carrera) if not tiene_balon_en_manos else 0.0
		var balon_actual: Balon3D = _obtener_balon_juego()
		var seg_balon_z: float = clampf((balon_actual.global_position.z - global_position.z) * 0.08, -0.14, 0.14) if (balon_actual and not tiene_balon_en_manos) else 0.0

		_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.26 + balanceo_lat * 0.12, delta * 12.0)
		_ang_pierna_der_x = lerpf(_ang_pierna_der_x, -0.26 - balanceo_lat * 0.12, delta * 12.0)
		_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.15, delta * 12.0)
		_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -0.15, delta * 12.0)
		_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.32, delta * 12.0)
		_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.32, delta * 12.0)

		if tiene_balon_en_manos or _estado == EstadoJugador.ESTADO_PORTERO_MANOS:
			_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 1.05, delta * 12.0)
			_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 1.05, delta * 12.0)
			_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.12, delta * 12.0)
			_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.12, delta * 12.0)
			_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.65, delta * 12.0)
			_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.65, delta * 12.0)
			if visual:
				visual.rotation.x = lerpf(visual.rotation.x, -0.04, delta * 12.0)
				visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 12.0)
				visual.position.y = lerpf(visual.position.y, 0.0, delta * 12.0)
		else:
			_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.52 + balanceo_lat * 0.08, delta * 12.0)
			_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.52 - balanceo_lat * 0.08, delta * 12.0)
			_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.44, delta * 12.0)
			_ang_brazo_der_z = lerpf(_ang_brazo_der_z, -0.44, delta * 12.0)
			_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.48, delta * 12.0)
			_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.48, delta * 12.0)
			if visual:
				visual.rotation.x = lerpf(visual.rotation.x, -0.14, delta * 10.0)
				visual.rotation.z = lerpf(visual.rotation.z, balanceo_lat * 0.06 + seg_balon_z, delta * 10.0)
				visual.position.y = lerpf(visual.position.y, abs(cos(_fase_carrera)) * 0.025, delta * 12.0)
		_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
		return

	# Resetear rotaciones Z laterales para jugadores de campo o durante ENTRADA
	_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.0, delta * 12.0)
	_ang_pierna_der_z = lerpf(_ang_pierna_der_z, 0.0, delta * 12.0)
	_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, 0.0, delta * 12.0)
	_ang_brazo_der_z = lerpf(_ang_brazo_der_z, 0.0, delta * 12.0)
	if visual:
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, delta * 12.0)

	# ==========================================================================
	# B. ANIMACIONES DE JUGADORES DE CAMPO (Y TROTE DE ENTRADA)
	# ==========================================================================
	# 1. Pose de barrida deslizante
	if _en_barrida:
		_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 1.15, delta * 18.0)
		_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, -0.55, delta * 18.0)
		_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.10, delta * 18.0)
		_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.95, delta * 18.0)
		_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, -0.7, delta * 18.0)
		_ang_brazo_der_x = lerpf(_ang_brazo_der_x, -0.7, delta * 18.0)
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.42, delta * 16.0)
			visual.position.y = lerpf(visual.position.y, -0.18, delta * 16.0)
		_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
		return

	# 1b. Pose compacta de Barrera de Tiro Libre (hombro con hombro protegiendo zona media/baja)
	if en_pose_barrera:
		_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.14, delta * 14.0)
		_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.14, delta * 14.0)
		_ang_pierna_izq_z = lerpf(_ang_pierna_izq_z, 0.04, delta * 14.0)
		_ang_pierna_der_z = lerpf(_ang_pierna_der_z, -0.04, delta * 14.0)
		_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, -0.22, delta * 14.0)
		_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, -0.22, delta * 14.0)
		_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.42, delta * 14.0)
		_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.42, delta * 14.0)
		_ang_brazo_izq_z = lerpf(_ang_brazo_izq_z, -0.24, delta * 14.0)
		_ang_brazo_der_z = lerpf(_ang_brazo_der_z, 0.24, delta * 14.0)
		_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.88, delta * 14.0)
		_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.88, delta * 14.0)
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, -0.06, delta * 14.0)
			visual.position.y = lerpf(visual.position.y, 0.0, delta * 14.0)
		_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
		return

	# 1c. Carrera previa de Tiro Libre (2-3 pasos rápidos de aproximación antes del impacto)
	if _en_carrera_tiro_libre:
		_fase_carrera = fmod(_fase_carrera + delta * 25.0, TAU)
		var onda_tl: float = sin(_fase_carrera)
		_ang_pierna_izq_x = onda_tl * 0.82
		_ang_pierna_der_x = -onda_tl * 0.82
		_ang_rodilla_izq_x = -clampf(0.24 + maxf(0.0, -onda_tl) * 0.82, 0.16, 1.05)
		_ang_rodilla_der_x = -clampf(0.24 + maxf(0.0, onda_tl) * 0.82, 0.16, 1.05)
		_ang_brazo_izq_x = -onda_tl * 0.68
		_ang_brazo_der_x = onda_tl * 0.68
		_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.65, delta * 16.0)
		_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.65, delta * 16.0)
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, -0.11, delta * 16.0)
			visual.position.y = abs(cos(_fase_carrera)) * 0.042
		_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
		return

	# 2. Animación de patada (tiro / pase / saque de banda con el pie)
	if _t_anim_patada > 0.0:
		var fase_patada: float = sin((_t_anim_patada / 0.28) * PI)
		_ang_pierna_der_x = fase_patada * 1.25
		_ang_pierna_izq_x = -fase_patada * 0.35
		_ang_rodilla_der_x = -maxf(0.0, -fase_patada) * 0.65
		_ang_rodilla_izq_x = -0.22 * absf(fase_patada)
		_ang_brazo_izq_x = fase_patada * 0.75
		_ang_brazo_der_x = -fase_patada * 0.55
		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.08 * fase_patada, delta * 15.0)
			visual.position.y = lerpf(visual.position.y, 0.0, delta * 15.0)
		_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)
		return

	# 3. Ciclo de carrera / trote de ENTRADA / conducción vs reposo
	if vel_plana > 0.2 and not _en_posicion_saque:
		var frec_zancada: float = 5.5 + vel_plana * 2.1
		_fase_carrera = fmod(_fase_carrera + delta * frec_zancada, TAU)
		var onda: float = sin(_fase_carrera)
		var amp_pierna: float = clampf(0.25 + vel_plana * 0.11, 0.25, 0.92)
		var amp_brazo: float = amp_pierna * 0.78

		_ang_pierna_izq_x = onda * amp_pierna
		_ang_pierna_der_x = -onda * amp_pierna
		_ang_rodilla_izq_x = -clampf(0.18 + maxf(0.0, -onda) * 0.75, 0.12, 0.95)
		_ang_rodilla_der_x = -clampf(0.18 + maxf(0.0, onda) * 0.75, 0.12, 0.95)
		_ang_brazo_izq_x = -onda * amp_brazo
		_ang_brazo_der_x = onda * amp_brazo
		_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.58, delta * 10.0)
		_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.58, delta * 10.0)

		if visual:
			var inclinacion_carrera: float = -0.09 if sprint_activo else -0.05
			visual.rotation.x = lerpf(visual.rotation.x, inclinacion_carrera, delta * 10.0)
			visual.position.y = abs(cos(_fase_carrera)) * 0.038
	else:
		_ang_pierna_izq_x = lerpf(_ang_pierna_izq_x, 0.0, delta * 12.0)
		_ang_pierna_der_x = lerpf(_ang_pierna_der_x, 0.0, delta * 12.0)
		_ang_rodilla_izq_x = lerpf(_ang_rodilla_izq_x, 0.0, delta * 12.0)
		_ang_rodilla_der_x = lerpf(_ang_rodilla_der_x, 0.0, delta * 12.0)
		_ang_brazo_izq_x = lerpf(_ang_brazo_izq_x, 0.0, delta * 12.0)
		_ang_brazo_der_x = lerpf(_ang_brazo_der_x, 0.0, delta * 12.0)
		_ang_codo_izq_z = lerpf(_ang_codo_izq_z, 0.28, delta * 12.0)
		_ang_codo_der_z = lerpf(_ang_codo_der_z, -0.28, delta * 12.0)

		if visual:
			visual.rotation.x = lerpf(visual.rotation.x, 0.0, delta * 12.0)
			visual.position.y = lerpf(visual.position.y, 0.0, delta * 12.0)

	_sincronizar_articulaciones_actuales(tiene_pivotes_legacy)


func _sincronizar_articulaciones_actuales(tiene_pivotes_legacy: bool) -> void:
	if esqueleto_humanoide != null:
		_aplicar_pose_esqueleto_actual()
	if tiene_pivotes_legacy:
		pivote_pierna_izq.rotation.x = _ang_pierna_izq_x
		pivote_pierna_der.rotation.x = _ang_pierna_der_x
		pivote_pierna_izq.rotation.z = _ang_pierna_izq_z
		pivote_pierna_der.rotation.z = _ang_pierna_der_z
		pivote_brazo_izq.rotation.x = _ang_brazo_izq_x
		pivote_brazo_der.rotation.x = _ang_brazo_der_x
		pivote_brazo_izq.rotation.z = _ang_brazo_izq_z
		pivote_brazo_der.rotation.z = _ang_brazo_der_z


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


## Retorna la velocidad máxima de sprint reglamentaria según el atributo OVR de vel_movimiento
func obtener_velocidad_sprint_max() -> float:
	var vel_base: float = 3.85 + (vel_movimiento / 99.0) * 1.75
	return vel_base * multiplicador_sprint


func establecer_sprint(activo: bool) -> void:
	_sprint_tactil_mantenido = activo
	sprint_activo = activo
	if not activo:
		_presion_sprint_defensivo = false


func establecer_sprint_y_presion(activo: bool, modo_defensa: bool = false) -> void:
	_sprint_tactil_mantenido = activo
	sprint_activo = activo
	_presion_sprint_defensivo = activo and modo_defensa


func establecer_direccion_virtual(dir: Vector2) -> void:
	direccion_virtual = dir


func _emitir_anuncio_hud(texto: String) -> void:
	var hud: HUDPartido = get_tree().get_first_node_in_group("hud_partido") as HUDPartido
	if hud and is_instance_valid(hud):
		hud.mostrar_anuncio(texto)


func _actualizar_colores_uniforme() -> void:
	aplicar_atlas_y_dorsal_compartido()


## Configura el sombreado suave (Smooth Shading) en mallas ArrayMesh y optimiza la proyección de sombras:
## - Desactiva emisión de sombras secundarias complejas en accesorios pequeños (escudo, manos, medias, botines, etiquetas).
## - Mantiene sombra direccional limpia únicamente en la silueta principal y proyecta sombra de contacto en el parquet.
func _configurar_geometria_y_sombras_midpoly() -> void:
	var mallas_silueta_principal: Array[MeshInstance3D] = [
		malla_cuerpo_glb, malla_camiseta_glb, malla_short_glb,
		torso_mesh, cabeza_mesh, pantalones_mesh,
		manga_izq_mesh, brazo_izq_mesh, manga_der_mesh, brazo_der_mesh,
		muslo_izq_mesh, pierna_izq_mesh, muslo_der_mesh, pierna_der_mesh
	]
	for m: MeshInstance3D in mallas_silueta_principal:
		if m != null:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var mallas_sin_sombra_secundaria: Array[MeshInstance3D] = [
		malla_pelo_glb, malla_pestanas_glb, malla_medias_glb, malla_botines_glb,
		escudo_pecho, cuello_mesh, pelo_mesh,
		mano_izq_mesh, mano_der_mesh,
		media_izq_mesh, media_der_mesh,
		botin_izq_mesh, botin_der_mesh,
		indicador_control, cuerpo_flecha_mesh, punta_flecha_mesh,
		sombra_contacto_piso
	]
	for m_sec: MeshInstance3D in mallas_sin_sombra_secundaria:
		if m_sec != null:
			m_sec.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if label_dorsal:
		label_dorsal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if label_nombre:
		label_nombre.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Si existe una malla unificada Mid-Poly importada (.glb / ArrayMesh), activar sombra limpia en ella
	# y recalcular normales suaves (Smooth Shading) + tangentes para el Normal Map.
	if malla_unificada_midpoly != null:
		malla_unificada_midpoly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if forzar_smooth_shading and malla_unificada_midpoly.mesh is ArrayMesh:
			_recalcular_smooth_normals_array_mesh(malla_unificada_midpoly.mesh as ArrayMesh)


## Fuerza Smooth Shading (grupo de suavizado continuo 0) y regenera tangentes MIKKT para Normal Map en un ArrayMesh
func _recalcular_smooth_shading_array_mesh(malla: ArrayMesh) -> void:
	_recalcular_smooth_normals_array_mesh(malla)


func _recalcular_smooth_normals_array_mesh(malla: ArrayMesh) -> void:
	if malla == null or malla.get_surface_count() == 0:
		return
	var nueva_malla: ArrayMesh = ArrayMesh.new()
	for idx_surf: int in range(malla.get_surface_count()):
		var st: SurfaceTool = SurfaceTool.new()
		st.create_from(malla, idx_surf)
		st.set_smooth_group(0)
		st.generate_normals()
		st.generate_tangents()
		st.commit(nueva_malla)
	if malla_unificada_midpoly:
		malla_unificada_midpoly.mesh = nueva_malla


## Obtiene o crea el único ShaderMaterial compartido por el lote del equipo (`LOCAL_CAMPO`, `LOCAL_PORTERO`,
## `VISITANTE_CAMPO`, `VISITANTE_PORTERO`). Garantiza que los jugadores del mismo equipo compartan la misma
## instancia de recurso Material para ejecutarse en un solo lote (Draw Call Batching) sin `.duplicate()`.
func _obtener_material_lote_equipo(clave_lote: String) -> ShaderMaterial:
	if _pool_materiales_atlas.has(clave_lote):
		var mat_existente: ShaderMaterial = _pool_materiales_atlas[clave_lote] as ShaderMaterial
		if mat_existente != null and is_instance_valid(mat_existente):
			return mat_existente

	var nuevo_mat: ShaderMaterial = ShaderMaterial.new()
	nuevo_mat.shader = SHADER_JUGADOR_MIDPOLY
	_pool_materiales_atlas[clave_lote] = nuevo_mat
	return nuevo_mat


## Aplica el Texture Atlas compartido por equipo (`jugador_midpoly.gdshader`) y diferencia el dorsal,
## variante de piel/cabello y zona UV de cada jugador mediante `set_instance_shader_parameter()`
## SIN duplicar el recurso Material (preservando el Draw Call Batching en móviles).
func aplicar_atlas_y_dorsal_compartido() -> void:
	if (
		malla_cuerpo_glb == null
		and malla_camiseta_glb == null
		and torso_mesh == null
		and malla_unificada_midpoly == null
	):
		return

	var es_loc: bool = (equipo == Equipo.LOCAL)
	var es_portero: bool = (posicion_tactica == "PORTERO")
	var info_eq: Dictionary = Futsal_3D.obtener_info_equipo(es_loc)

	# 1. Paleta base diferenciada por equipo: RFC (Rojo/Negro) vs ASF (Amarillo/Azul Marino)
	var col_camiseta: Color = Color(0.85, 0.15, 0.15) if es_loc else Color(0.95, 0.85, 0.10)
	var col_escudo: Color = Color(0.95, 0.80, 0.20) if es_loc else Color(0.12, 0.30, 0.65)
	var col_short: Color = Color(0.10, 0.12, 0.18) if es_loc else Color(0.08, 0.14, 0.28)
	var col_medias: Color = col_camiseta
	var col_botines: Color = Color(0.12, 0.14, 0.18)

	if not info_eq.is_empty():
		col_camiseta = Color.from_string(str(info_eq.get("color_primario", "")), col_camiseta)
		col_escudo = Color.from_string(str(info_eq.get("color_secundario", "")), col_escudo)
		col_short = Color.from_string(str(info_eq.get("color_short", "")), col_short)
		col_medias = col_camiseta

	# Arqueros con equipación alternativa contrastante
	if es_portero:
		var hex_gk: String = str(info_eq.get("color_arquero", ""))
		if es_loc:
			col_camiseta = Color.from_string(hex_gk, Color(0.10, 0.78, 0.28))
			col_short = Color(0.06, 0.20, 0.12)
		else:
			col_camiseta = Color.from_string(hex_gk, Color(0.96, 0.42, 0.08))
			col_short = Color(0.12, 0.14, 0.22)
		col_medias = col_camiseta

	# 2. Recuperar el ShaderMaterial único compartido por el lote del equipo (0 duplicaciones por jugador)
	var prefijo_eq: String = "LOCAL" if es_loc else "VISITANTE"
	var sufijo_rol: String = "PORTERO" if es_portero else "CAMPO"
	var clave_lote: String = "%s_%s" % [prefijo_eq, sufijo_rol]
	var mat_compartido: ShaderMaterial = _obtener_material_lote_equipo(clave_lote)

	mat_compartido.set_shader_parameter("color_camiseta", col_camiseta)
	mat_compartido.set_shader_parameter("color_secundario", col_escudo)
	mat_compartido.set_shader_parameter("color_short", col_short)
	mat_compartido.set_shader_parameter("color_medias", col_medias)
	mat_compartido.set_shader_parameter("color_botines", col_botines)

	var tex_albedo_efectiva: Texture2D = (
		textura_atlas_albedo
		if textura_atlas_albedo != null
		else _textura_glb_albedo_cache
	)
	if tex_albedo_efectiva != null:
		mat_compartido.set_shader_parameter("textura_atlas_albedo", tex_albedo_efectiva)
		mat_compartido.set_shader_parameter("mezcla_textura_atlas", 1.0)
	else:
		mat_compartido.set_shader_parameter("mezcla_textura_atlas", 0.0)

	var tex_normal_efectiva: Texture2D = (
		textura_atlas_normal
		if textura_atlas_normal != null
		else _textura_glb_normal_cache
	)
	if tex_normal_efectiva != null:
		mat_compartido.set_shader_parameter("textura_atlas_normal", tex_normal_efectiva)
	if textura_atlas_orm != null:
		mat_compartido.set_shader_parameter("textura_atlas_orm", textura_atlas_orm)

	# 3. Variante de piel/pelo y dorsal por instancia (vía Instance Uniforms sin clonar el Material)
	var var_aspecto: int = variante_aspecto_facial if variante_aspecto_facial >= 0 else (absi(dorsal) % 4)

	# A. Caso Malla Unificada Mid-Poly con UVs empaquetadas en los 4 cuadrantes del Atlas (id_zona_malla = 0)
	if malla_unificada_midpoly != null:
		malla_unificada_midpoly.material_override = mat_compartido
		malla_unificada_midpoly.set_instance_shader_parameter("id_zona_malla", 0)
		malla_unificada_midpoly.set_instance_shader_parameter("dorsal_jugador", dorsal)
		malla_unificada_midpoly.set_instance_shader_parameter("variante_aspecto", var_aspecto)

	# B. Caso Modelo Humanoide Importado (`Jugador_Futsal.glb`):
	#    Conectar el shader `jugador_midpoly.gdshader` compartido a todas las mallas `Ch38_*`
	#    (1:Piel/Rostro, 2:Pelo/Pestañas, 3:Camiseta, 5:Shorts, 6:Medias, 7:Botines)
	_asignar_zona_instancia_malla(malla_cuerpo_glb, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_pelo_glb, mat_compartido, 2, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_pestanas_glb, mat_compartido, 2, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_camiseta_glb, mat_compartido, 3, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_short_glb, mat_compartido, 5, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_medias_glb, mat_compartido, 6, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(malla_botines_glb, mat_compartido, 7, dorsal, var_aspecto)

	# C. Fallback compatible para nodos modulares antiguos si estuvieran presentes
	_asignar_zona_instancia_malla(torso_mesh, mat_compartido, 3, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(manga_izq_mesh, mat_compartido, 3, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(manga_der_mesh, mat_compartido, 3, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(escudo_pecho, mat_compartido, 4, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(pantalones_mesh, mat_compartido, 5, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(muslo_izq_mesh, mat_compartido, 5, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(muslo_der_mesh, mat_compartido, 5, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(media_izq_mesh, mat_compartido, 6, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(media_der_mesh, mat_compartido, 6, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(botin_izq_mesh, mat_compartido, 7, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(botin_der_mesh, mat_compartido, 7, dorsal, var_aspecto)

	_asignar_zona_instancia_malla(cuello_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(cabeza_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(brazo_izq_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(brazo_der_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(pierna_izq_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(pierna_der_mesh, mat_compartido, 1, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(pelo_mesh, mat_compartido, 2, dorsal, var_aspecto)

	# En porteros, las manos utilizan la zona 4/7 (guantes) en lugar de piel
	var zona_manos: int = 4 if es_portero else 1
	_asignar_zona_instancia_malla(mano_izq_mesh, mat_compartido, zona_manos, dorsal, var_aspecto)
	_asignar_zona_instancia_malla(mano_der_mesh, mat_compartido, zona_manos, dorsal, var_aspecto)

	if label_dorsal:
		label_dorsal.text = str(dorsal)


func _asignar_zona_instancia_malla(
	malla: MeshInstance3D,
	mat_lote: ShaderMaterial,
	id_zona: int,
	num_dorsal: int,
	var_aspecto: int
) -> void:
	if malla == null:
		return
	malla.material_override = mat_lote
	malla.set_instance_shader_parameter("id_zona_malla", id_zona)
	malla.set_instance_shader_parameter("dorsal_jugador", num_dorsal)
	malla.set_instance_shader_parameter("variante_aspecto", var_aspecto)


# ==============================================================================
# HITBOXES Y DETECCIÓN ANATÓMICA DE ATAJADAS DEL ARQUERO (FIFA / EFOOTBALL)
# ==============================================================================

## Configura las 4 zonas anatómicas de contacto del arquero (Manos, Pecho, Piernas, Cabeza)
func _configurar_hitboxes_anatomicas_portero() -> void:
	if not (es_arquero or posicion_tactica == "PORTERO"):
		return
	
	# 1. AreaManos: Cubriendo las manos y muñecas
	area_manos = get_node_or_null("AreaManos") as Area3D
	if area_manos == null and visual != null:
		area_manos = visual.get_node_or_null("AreaManos") as Area3D
	if area_manos == null:
		area_manos = Area3D.new()
		area_manos.name = "AreaManos"
		var col_manos: CollisionShape3D = CollisionShape3D.new()
		col_manos.name = "ShapeManos"
		var box_manos: BoxShape3D = BoxShape3D.new()
		box_manos.size = Vector3(0.95, 0.48, 0.42)
		col_manos.shape = box_manos
		col_manos.position = Vector3(0.0, 1.20, -0.38)
		area_manos.add_child(col_manos)
		add_child(area_manos)
	_configurar_propiedades_hitbox(area_manos, "manos")
	
	# 2. AreaPecho: Cubriendo el torso superior
	area_pecho = get_node_or_null("AreaPecho") as Area3D
	if area_pecho == null and visual != null:
		area_pecho = visual.get_node_or_null("AreaPecho") as Area3D
	if area_pecho == null:
		area_pecho = Area3D.new()
		area_pecho.name = "AreaPecho"
		var col_pecho: CollisionShape3D = CollisionShape3D.new()
		col_pecho.name = "ShapePecho"
		var box_pecho: BoxShape3D = BoxShape3D.new()
		box_pecho.size = Vector3(0.62, 0.52, 0.38)
		col_pecho.shape = box_pecho
		col_pecho.position = Vector3(0.0, 1.25, -0.04)
		area_pecho.add_child(col_pecho)
		add_child(area_pecho)
	_configurar_propiedades_hitbox(area_pecho, "pecho")
	
	# 3. AreaPiernas: Cubriendo espinillas y botines
	area_piernas = get_node_or_null("AreaPiernas") as Area3D
	if area_piernas == null and visual != null:
		area_piernas = visual.get_node_or_null("AreaPiernas") as Area3D
	if area_piernas == null:
		area_piernas = Area3D.new()
		area_piernas.name = "AreaPiernas"
		var col_piernas: CollisionShape3D = CollisionShape3D.new()
		col_piernas.name = "ShapePiernas"
		var box_piernas: BoxShape3D = BoxShape3D.new()
		box_piernas.size = Vector3(0.75, 0.72, 0.45)
		col_piernas.shape = box_piernas
		col_piernas.position = Vector3(0.0, 0.40, -0.05)
		area_piernas.add_child(col_piernas)
		add_child(area_piernas)
	_configurar_propiedades_hitbox(area_piernas, "piernas")
	
	# 4. AreaCabeza: Cubriendo la cabeza
	area_cabeza = get_node_or_null("AreaCabeza") as Area3D
	if area_cabeza == null and visual != null:
		area_cabeza = visual.get_node_or_null("AreaCabeza") as Area3D
	if area_cabeza == null:
		area_cabeza = Area3D.new()
		area_cabeza.name = "AreaCabeza"
		var col_cabeza: CollisionShape3D = CollisionShape3D.new()
		col_cabeza.name = "ShapeCabeza"
		var sphere_cabeza: SphereShape3D = SphereShape3D.new()
		sphere_cabeza.radius = 0.24
		col_cabeza.shape = sphere_cabeza
		col_cabeza.position = Vector3(0.0, 1.68, 0.0)
		area_cabeza.add_child(col_cabeza)
		add_child(area_cabeza)
	_configurar_propiedades_hitbox(area_cabeza, "cabeza")


func _configurar_propiedades_hitbox(area: Area3D, zona: String) -> void:
	if area == null:
		return
	area.set_meta("zona_cuerpo", zona)
	area.set_meta("arquero", self)
	if not area.is_in_group("hitbox_arquero"):
		area.add_to_group("hitbox_arquero")
	var grupo_zona: String = "zona_" + zona
	if not area.is_in_group(grupo_zona):
		area.add_to_group(grupo_zona)
	
	area.collision_layer = 0
	area.collision_mask = 1 # Capa 1: Balon3D RigidBody3D
	area.monitoring = true
	area.monitorable = true
	
	var cb: Callable = Callable(self, "_on_hitbox_arquero_body_entered").bind(zona)
	if not area.body_entered.is_connected(cb):
		area.body_entered.connect(cb)


func _on_hitbox_arquero_body_entered(body: Node3D, zona: String) -> void:
	if body is Balon3D:
		var balon_obj: Balon3D = body as Balon3D
		if balon_obj and not balon_obj.esta_fuera_de_juego:
			match zona:
				"piernas":
					_tipo_atajada_actual = EstadoJugador.ATAJADA_BAJA
					_t_anim_atajada = 0.50
					_lado_atajada = 1.0 if body.global_position.z >= global_position.z else -1.0
				"pecho", "cabeza":
					_tipo_atajada_actual = EstadoJugador.ATAJADA_MEDIA
					_t_anim_atajada = 0.46
				"manos":
					_t_anim_atajada = 0.35
			
			balon_obj.procesar_impacto_arquero(zona, self)


## Sincroniza la posición de las hitboxes anatómicas ante cambios dinámicos de pose del arquero
func _actualizar_hitboxes_portero() -> void:
	if not (es_arquero or posicion_tactica == "PORTERO"):
		return
	if area_piernas == null or area_pecho == null:
		return
	
	if _estado == EstadoJugador.ACHIQUE_CRUZ_K or _en_achique_cruz_k:
		area_pecho.position = Vector3(0.0, 0.98, -0.12)
		area_piernas.position = Vector3(0.0, 0.28, _lado_atajada * 0.25)
		if area_manos:
			area_manos.position = Vector3(0.0, 0.95, -0.42)
	elif _estado == EstadoJugador.ATAJADA_BAJA or (_t_anim_atajada > 0.0 and _tipo_atajada_actual == EstadoJugador.ATAJADA_BAJA):
		area_piernas.position = Vector3(0.0, 0.30, _lado_atajada * 0.38)
		area_pecho.position = Vector3(0.0, 1.25, -0.04)
		if area_manos:
			area_manos.position = Vector3(0.0, 1.15, -0.32)
	else:
		area_pecho.position = Vector3(0.0, 1.25, -0.04)
		area_piernas.position = Vector3(0.0, 0.40, -0.05)
		if area_manos:
			area_manos.position = Vector3(0.0, 1.20, -0.38)
		if area_cabeza:
			area_cabeza.position = Vector3(0.0, 1.68, 0.0)


## Configura el sistema de colisiones segmentado de la barrera defensiva:
## a) Grupo "Torso_Legs_Head": cabeza, tronco, muslos y piernas (bloqueo reglamentario).
## b) Grupo "Arms_Hands": antebrazos, brazos y manos sobresalientes en T-Pose (infracción de mano).
func _configurar_hitboxes_barrera() -> void:
	if area_torso_piernas_cabeza != null and area_brazos_manos != null:
		return

	# 1. AreaTorsoLegsHead (Bloqueo legal: cabeza, tronco, muslos y piernas)
	area_torso_piernas_cabeza = get_node_or_null("AreaTorsoLegsHead") as Area3D
	if area_torso_piernas_cabeza == null and visual != null:
		area_torso_piernas_cabeza = visual.get_node_or_null("AreaTorsoLegsHead") as Area3D
	if area_torso_piernas_cabeza == null:
		area_torso_piernas_cabeza = Area3D.new()
		area_torso_piernas_cabeza.name = "AreaTorsoLegsHead"
		var col_torso: CollisionShape3D = CollisionShape3D.new()
		col_torso.name = "ShapeTorsoLegsHead"
		var capsule_torso: CapsuleShape3D = CapsuleShape3D.new()
		capsule_torso.radius = 0.28
		capsule_torso.height = 1.82
		col_torso.shape = capsule_torso
		col_torso.position = Vector3(0.0, 0.91, 0.0)
		area_torso_piernas_cabeza.add_child(col_torso)
		add_child(area_torso_piernas_cabeza)

	area_torso_piernas_cabeza.set_meta("zona_cuerpo", "Torso_Legs_Head")
	area_torso_piernas_cabeza.set_meta("defensor", self)
	if not area_torso_piernas_cabeza.is_in_group("Torso_Legs_Head"):
		area_torso_piernas_cabeza.add_to_group("Torso_Legs_Head")
	if not area_torso_piernas_cabeza.is_in_group("hitbox_defensor"):
		area_torso_piernas_cabeza.add_to_group("hitbox_defensor")
	if not area_torso_piernas_cabeza.is_in_group("barrera_bloqueo"):
		area_torso_piernas_cabeza.add_to_group("barrera_bloqueo")

	area_torso_piernas_cabeza.collision_layer = 2
	area_torso_piernas_cabeza.collision_mask = 1
	area_torso_piernas_cabeza.monitoring = en_pose_barrera
	area_torso_piernas_cabeza.monitorable = en_pose_barrera

	var cb_torso: Callable = Callable(self, "_on_hitbox_barrera_body_entered").bind("Torso_Legs_Head")
	if not area_torso_piernas_cabeza.body_entered.is_connected(cb_torso):
		area_torso_piernas_cabeza.body_entered.connect(cb_torso)

	# 2. AreaArmsHands (Infracción de mano en T-Pose: brazos, antebrazos y manos sobresalientes)
	area_brazos_manos = get_node_or_null("AreaArmsHands") as Area3D
	if area_brazos_manos == null and visual != null:
		area_brazos_manos = visual.get_node_or_null("AreaArmsHands") as Area3D
	if area_brazos_manos == null:
		area_brazos_manos = Area3D.new()
		area_brazos_manos.name = "AreaArmsHands"

		# Brazo / mano izquierda sobresaliente
		var col_brazo_izq: CollisionShape3D = CollisionShape3D.new()
		col_brazo_izq.name = "ShapeBrazoIzq"
		var box_izq: BoxShape3D = BoxShape3D.new()
		box_izq.size = Vector3(0.56, 0.24, 0.26)
		col_brazo_izq.shape = box_izq
		col_brazo_izq.position = Vector3(-0.56, 1.35, 0.0)
		area_brazos_manos.add_child(col_brazo_izq)

		# Brazo / mano derecha sobresaliente
		var col_brazo_der: CollisionShape3D = CollisionShape3D.new()
		col_brazo_der.name = "ShapeBrazoDer"
		var box_der: BoxShape3D = BoxShape3D.new()
		box_der.size = Vector3(0.56, 0.24, 0.26)
		col_brazo_der.shape = box_der
		col_brazo_der.position = Vector3(0.56, 1.35, 0.0)
		area_brazos_manos.add_child(col_brazo_der)

		add_child(area_brazos_manos)

	area_brazos_manos.set_meta("zona_cuerpo", "Arms_Hands")
	area_brazos_manos.set_meta("defensor", self)
	if not area_brazos_manos.is_in_group("Arms_Hands"):
		area_brazos_manos.add_to_group("Arms_Hands")
	if not area_brazos_manos.is_in_group("hitbox_defensor"):
		area_brazos_manos.add_to_group("hitbox_defensor")
	if not area_brazos_manos.is_in_group("barrera_mano"):
		area_brazos_manos.add_to_group("barrera_mano")

	establecer_sancion_manos_barrera(sancionar_manos_barrera)

	var cb_brazos: Callable = Callable(self, "_on_hitbox_barrera_body_entered").bind("Arms_Hands")
	if not area_brazos_manos.body_entered.is_connected(cb_brazos):
		area_brazos_manos.body_entered.connect(cb_brazos)


## Inhabilita o habilita la capa de colisión de los brazos/manos.
## Al desactivarse, el tiro solo responde a la silueta del torso y piernas cerradas
## (emulando la postura real de barrera con manos pegadas a la espalda).
func establecer_sancion_manos_barrera(habilitar: bool) -> void:
	if area_brazos_manos == null:
		return
	if habilitar and en_pose_barrera:
		area_brazos_manos.collision_layer = 2
		area_brazos_manos.collision_mask = 1
		area_brazos_manos.monitoring = true
		area_brazos_manos.monitorable = true
	else:
		area_brazos_manos.collision_layer = 0
		area_brazos_manos.collision_mask = 0
		area_brazos_manos.monitoring = false
		area_brazos_manos.monitorable = false


func _on_hitbox_barrera_body_entered(body: Node3D, zona: String) -> void:
	if body is Balon3D:
		var balon_obj: Balon3D = body as Balon3D
		if balon_obj and not balon_obj.esta_fuera_de_juego:
			balon_obj.procesar_impacto_barrera(zona, self, balon_obj.global_position)


