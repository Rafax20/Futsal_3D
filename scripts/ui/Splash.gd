class_name Splash
extends Control

## Pantalla de bienvenida y carga inicial estilo EA Sports / FC Mobile.
## Anima una barra de progreso sutil y navega al Menú Principal tras 2 segundos.

@export var tiempo_carga: float = 2.0
@export var escena_siguiente: String = "res://scenes/ui/MainMenu.tscn"

@onready var barra_progreso: ProgressBar = $Centro/VBox/BarraProgreso
@onready var label_estado: Label = $Centro/VBox/LabelEstado

var _tiempo_acumulado: float = 0.0
var _cambio_realizado: bool = false


func _ready() -> void:
	if barra_progreso:
		barra_progreso.value = 0.0


func _process(delta: float) -> void:
	if _cambio_realizado:
		return
	
	_tiempo_acumulado += delta
	var progreso: float = clampf(_tiempo_acumulado / tiempo_carga, 0.0, 1.0)
	
	if barra_progreso:
		barra_progreso.value = progreso * 100.0
	
	if label_estado:
		if progreso < 0.35:
			label_estado.text = "Iniciando motor de físicas Jolt 3D..."
		elif progreso < 0.75:
			label_estado.text = "Cargando cancha y formaciones 5v5..."
		else:
			label_estado.text = "¡Listo para saltar a la pista!"
	
	if _tiempo_acumulado >= tiempo_carga:
		_cambio_realizado = true
		get_tree().change_scene_to_file(escena_siguiente)
