class_name FiguraArbitro3D
extends Node3D

## Representación procedural 3D del Árbitro de Fútsal para cinemáticas de faltas y amonestaciones.
## Despliega una figura anatómica con uniforme arbitral oficial (negro/cian neón) y animación
## procedural para levantar el brazo exhibiendo la tarjeta amarilla o roja en alto.

var _pivote_brazo_der: Node3D = null
var _tarjeta_mesh: MeshInstance3D = null
var _mat_tarjeta: StandardMaterial3D = null
var _mallas: Array[MeshInstance3D] = []


func _ready() -> void:
	add_to_group("arbitro_3d")
	_construir_modelo_arbitro()


func _construir_modelo_arbitro() -> void:
	# 1. Materiales de indumentaria arbitral
	var mat_camiseta: StandardMaterial3D = StandardMaterial3D.new()
	mat_camiseta.albedo_color = Color(0.12, 0.14, 0.18, 1.0) # Negro grafito arbitral
	mat_camiseta.roughness = 0.55
	
	var mat_detalle_neon: StandardMaterial3D = StandardMaterial3D.new()
	mat_detalle_neon.albedo_color = Color(0.15, 0.88, 0.82, 1.0) # Cian neón oficial
	mat_detalle_neon.emission_enabled = true
	mat_detalle_neon.emission = Color(0.15, 0.88, 0.82, 1.0)
	mat_detalle_neon.emission_energy_multiplier = 0.45
	
	var mat_piel: StandardMaterial3D = StandardMaterial3D.new()
	mat_piel.albedo_color = Color(0.82, 0.64, 0.52, 1.0)
	mat_piel.roughness = 0.70
	
	var mat_pantalon: StandardMaterial3D = StandardMaterial3D.new()
	mat_pantalon.albedo_color = Color(0.08, 0.08, 0.10, 1.0)
	
	var mat_calzado: StandardMaterial3D = StandardMaterial3D.new()
	mat_calzado.albedo_color = Color(0.05, 0.05, 0.06, 1.0)

	# 2. Torso
	var torso: MeshInstance3D = MeshInstance3D.new()
	torso.name = "Torso"
	var box_torso: BoxMesh = BoxMesh.new()
	box_torso.size = Vector3(0.42, 0.55, 0.24)
	torso.mesh = box_torso
	torso.position = Vector3(0.0, 1.25, 0.0)
	torso.material_override = mat_camiseta
	add_child(torso)
	_mallas.append(torso)

	# Franja/Escudo cian neón en el pecho
	var escudo: MeshInstance3D = MeshInstance3D.new()
	var box_escudo: BoxMesh = BoxMesh.new()
	box_escudo.size = Vector3(0.08, 0.10, 0.02)
	escudo.mesh = box_escudo
	escudo.position = Vector3(0.10, 1.35, 0.125)
	escudo.material_override = mat_detalle_neon
	add_child(escudo)
	_mallas.append(escudo)

	# 3. Cabeza y cuello
	var cabeza: MeshInstance3D = MeshInstance3D.new()
	var sphere_cabeza: SphereMesh = SphereMesh.new()
	sphere_cabeza.radius = 0.12
	sphere_cabeza.height = 0.24
	cabeza.mesh = sphere_cabeza
	cabeza.position = Vector3(0.0, 1.66, 0.0)
	cabeza.material_override = mat_piel
	add_child(cabeza)
	_mallas.append(cabeza)

	# 4. Piernas y calzado
	var pierna_izq: MeshInstance3D = MeshInstance3D.new()
	var box_pierna: BoxMesh = BoxMesh.new()
	box_pierna.size = Vector3(0.15, 0.85, 0.18)
	pierna_izq.mesh = box_pierna
	pierna_izq.position = Vector3(-0.12, 0.45, 0.0)
	pierna_izq.material_override = mat_pantalon
	add_child(pierna_izq)
	_mallas.append(pierna_izq)

	var pierna_der: MeshInstance3D = MeshInstance3D.new()
	pierna_der.mesh = box_pierna
	pierna_der.position = Vector3(0.12, 0.45, 0.0)
	pierna_der.material_override = mat_pantalon
	add_child(pierna_der)
	_mallas.append(pierna_der)

	# 5. Brazo Izquierdo (al costado)
	var brazo_izq: MeshInstance3D = MeshInstance3D.new()
	var box_brazo: BoxMesh = BoxMesh.new()
	box_brazo.size = Vector3(0.12, 0.58, 0.13)
	brazo_izq.mesh = box_brazo
	brazo_izq.position = Vector3(-0.28, 1.20, 0.0)
	brazo_izq.material_override = mat_camiseta
	add_child(brazo_izq)
	_mallas.append(brazo_izq)

	# 6. Brazo Derecho Articulado (Pivote para levantar la tarjeta)
	_pivote_brazo_der = Node3D.new()
	_pivote_brazo_der.name = "PivoteBrazoDer"
	_pivote_brazo_der.position = Vector3(0.26, 1.48, 0.0)
	add_child(_pivote_brazo_der)

	var antebrazo_der: MeshInstance3D = MeshInstance3D.new()
	var box_antebrazo: BoxMesh = BoxMesh.new()
	box_antebrazo.size = Vector3(0.11, 0.55, 0.12)
	antebrazo_der.mesh = box_antebrazo
	antebrazo_der.position = Vector3(0.0, 0.28, 0.0) # Extendido hacia arriba desde el hombro
	antebrazo_der.material_override = mat_camiseta
	_pivote_brazo_der.add_child(antebrazo_der)
	_mallas.append(antebrazo_der)

	# Mano derecha
	var mano_der: MeshInstance3D = MeshInstance3D.new()
	var box_mano: BoxMesh = BoxMesh.new()
	box_mano.size = Vector3(0.08, 0.10, 0.09)
	mano_der.mesh = box_mano
	mano_der.position = Vector3(0.0, 0.58, 0.0)
	mano_der.material_override = mat_piel
	_pivote_brazo_der.add_child(mano_der)
	_mallas.append(mano_der)

	# 7. Tarjeta Arbitral (Amarilla / Roja)
	_mat_tarjeta = StandardMaterial3D.new()
	_mat_tarjeta.albedo_color = Color(1.0, 0.88, 0.05, 1.0)
	_mat_tarjeta.emission_enabled = true
	_mat_tarjeta.emission = Color(1.0, 0.88, 0.05, 1.0)
	_mat_tarjeta.emission_energy_multiplier = 0.65
	_mat_tarjeta.roughness = 0.25

	_tarjeta_mesh = MeshInstance3D.new()
	_tarjeta_mesh.name = "TarjetaArbitro"
	var box_tarjeta: BoxMesh = BoxMesh.new()
	box_tarjeta.size = Vector3(0.08, 0.16, 0.015)
	_tarjeta_mesh.mesh = box_tarjeta
	_tarjeta_mesh.position = Vector3(0.0, 0.68, 0.0)
	_tarjeta_mesh.material_override = _mat_tarjeta
	_pivote_brazo_der.add_child(_tarjeta_mesh)
	_mallas.append(_tarjeta_mesh)


## Configura la tarjeta y activa la animación procedural de levantar el brazo
func aparecer_y_mostrar_tarjeta(
	pos_infractor: Vector3,
	dir_arbitro_a_infractor: Vector3,
	tipo_tarjeta: String
) -> void:
	# Color de la tarjeta según sanción
	if _mat_tarjeta:
		if tipo_tarjeta == "ROJA_DIRECTA" or tipo_tarjeta == "SEGUNDA_AMARILLA":
			_mat_tarjeta.albedo_color = Color(0.95, 0.12, 0.12, 1.0)
			_mat_tarjeta.emission = Color(0.95, 0.12, 0.12, 1.0)
		else:
			_mat_tarjeta.albedo_color = Color(1.0, 0.88, 0.05, 1.0)
			_mat_tarjeta.emission = Color(1.0, 0.88, 0.05, 1.0)

	# Ubicación a 1.85 m frente al infractor encarándolo
	var dir_plana: Vector3 = Vector3(dir_arbitro_a_infractor.x, 0.0, dir_arbitro_a_infractor.z).normalized()
	if dir_plana.length_squared() < 0.01:
		dir_plana = Vector3(1.0, 0.0, 0.0)
	
	global_position = pos_infractor + dir_plana * 1.85
	global_position.y = 0.0
	rotation.y = atan2(-dir_plana.x, -dir_plana.z) + PI

	# Animación procedural de elevación de la tarjeta (de la cintura al cielo)
	if _pivote_brazo_der:
		_pivote_brazo_der.rotation_degrees.x = -85.0 # Apuntando hacia abajo/pecho inicialmente
		var tw: Tween = create_tween().set_ignore_time_scale(true)
		tw.tween_property(_pivote_brazo_der, "rotation_degrees:x", 12.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Establece el sesgo de LOD en todas las mallas del árbitro
func establecer_lod_bias(bias: float) -> void:
	for m: MeshInstance3D in _mallas:
		if m and is_instance_valid(m):
			m.lod_bias = bias


## Retira la figura de la escena
func desaparecer() -> void:
	var tw: Tween = create_tween().set_ignore_time_scale(true)
	tw.tween_property(self, "scale", Vector3.ZERO, 0.20).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)
