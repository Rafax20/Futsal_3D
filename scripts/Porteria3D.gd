class_name Porteria3D
extends Node3D

## Controlador de la portería 3D de fútsal.
## Gestiona la estructura física del marco (postes y travesaño cilíndricos con alto rebote),
## la red amortiguadora (alta fricción, bajo rebote) y el detector reglamentario de gol.

signal gol_detectado(balon: Balon3D)

@export var es_porteria_derecha: bool = true

@onready var marco_postes: StaticBody3D = $MarcoPostes as StaticBody3D
@onready var red_colision: StaticBody3D = $RedColision as StaticBody3D
@onready var goal_trigger: Area3D = $GoalTrigger as Area3D


func _ready() -> void:
	add_to_group("porteria")
	if marco_postes:
		marco_postes.add_to_group("postes_arco")
	if red_colision:
		red_colision.add_to_group("red_porteria")
	if goal_trigger:
		goal_trigger.add_to_group("detector_gol")
		if not goal_trigger.body_entered.is_connected(_on_goal_trigger_body_entered):
			goal_trigger.body_entered.connect(_on_goal_trigger_body_entered)


func _on_goal_trigger_body_entered(body: Node3D) -> void:
	var balon: Balon3D = body as Balon3D
	if balon == null and body != null and body.is_in_group("balon"):
		balon = body as Balon3D
	
	if balon != null:
		if balon.has_method("es_gol_valido_posicional") and not balon.es_gol_valido_posicional(es_porteria_derecha):
			return
		gol_detectado.emit(balon)
