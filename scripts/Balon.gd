class_name Balon
extends RigidBody2D

## Propiedades físicas para simular el comportamiento de un balón de futsal (medio pique).

@export_group("Física de Futsal")
## Coeficiente de restitución / rebote amortiguado (en futsal es bajo, típicamente entre 0.3 y 0.4).
@export_range(0.0, 1.0, 0.05) var rebote_amortiguado: float = 0.35:
	set(valor):
		rebote_amortiguado = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.bounce = valor

## Coeficiente de fricción en impactos con paredes, porterías y jugadores.
@export_range(0.0, 1.0, 0.05) var friccion_contacto: float = 0.25:
	set(valor):
		friccion_contacto = valor
		if is_node_ready() and physics_material_override:
			physics_material_override.friction = valor

## Amortiguación lineal que simula la fricción de rodadura contra la pista (linear_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_suelo: float = 1.2:
	set(valor):
		amortiguacion_suelo = valor
		linear_damp = valor

## Amortiguación angular que desacelera la rotación del balón sobre su eje (angular_damp).
@export_range(0.0, 10.0, 0.1) var amortiguacion_giro: float = 2.0:
	set(valor):
		amortiguacion_giro = valor
		angular_damp = valor

@export_group("Límites de Movimiento")
## Velocidad máxima del balón para evitar túneles de colisión a altas velocidades.
@export var velocidad_maxima: float = 1200.0

## Umbral de velocidad por debajo del cual el balón frena por completo.
@export var umbral_detencion: float = 4.0

# Referencias directas a los nodos definidos en la escena
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var sprite_2d: Sprite2D = $Sprite2D


func _ready() -> void:
	_configurar_fisicas()


func _physics_process(_delta: float) -> void:
	_controlar_velocidad()


func _configurar_fisicas() -> void:
	# En vista cenital 2D (top-down), la gravedad de pantalla debe ser nula
	gravity_scale = 0.0
	linear_damp = amortiguacion_suelo
	angular_damp = amortiguacion_giro
	
	if physics_material_override == null:
		physics_material_override = PhysicsMaterial.new()
	
	physics_material_override.bounce = rebote_amortiguado
	physics_material_override.friction = friccion_contacto


func _controlar_velocidad() -> void:
	var vel_actual: float = linear_velocity.length()
	
	# Limitar a velocidad máxima
	if vel_actual > velocidad_maxima:
		linear_velocity = linear_velocity.normalized() * velocidad_maxima
	# Detener completamente si la velocidad residual es mínima
	elif vel_actual > 0.0 and vel_actual < umbral_detencion:
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0


## Aplica un impulso al balón (por ejemplo, al patear o pasar).
func patear(fuerza: Vector2) -> void:
	apply_central_impulse(fuerza)


## Detiene completamente el movimiento lineal y rotacional del balón.
func detener() -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0


## Restablece la posición del balón y anula sus fuerzas (ej. saque de centro).
func reiniciar_posicion(nueva_posicion: Vector2) -> void:
	detener()
	global_position = nueva_posicion
