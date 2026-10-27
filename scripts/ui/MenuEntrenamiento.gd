class_name MenuEntrenamiento
extends Control

## Menú de Selección de Entrenamiento inspirado en eFootball Mobile.
## Presenta una cuadrícula limpia con los modos de práctica y conecta cada botón
## a un método genérico `_on_modo_seleccionado(nombre_modo: String)`.

@onready var btn_volver: Button = $MargenSuperior/BarraSuperior/BotonVolver
@onready var btn_tiro_libre: Button = $MargenPrincipal/VBoxContenido/GridModos/TarjetaTiroLibre/VBox/BotonSeleccionar
@onready var btn_ofensivo: Button = $MargenPrincipal/VBoxContenido/GridModos/TarjetaOfensivo/VBox/BotonSeleccionar
@onready var btn_partido_practica: Button = $MargenPrincipal/VBoxContenido/GridModos/TarjetaPartidoPractica/VBox/BotonSeleccionar
@onready var btn_corner: Button = $MargenPrincipal/VBoxContenido/GridModos/TarjetaCorner/VBox/BotonSeleccionar
@onready var btn_penales: Button = $MargenPrincipal/VBoxContenido/GridModos/TarjetaPenales/VBox/BotonSeleccionar

@onready var panel_aviso: PanelContainer = $PanelAvisoTemporal
@onready var label_aviso: Label = $PanelAvisoTemporal/LabelAviso

var _tween_aviso: Tween = null


func _ready() -> void:
	if panel_aviso:
		panel_aviso.visible = false
	_conectar_botones()


func _conectar_botones() -> void:
	if btn_volver:
		btn_volver.pressed.connect(_on_volver_pressed)
	
	if btn_tiro_libre:
		btn_tiro_libre.pressed.connect(_on_modo_seleccionado.bind("Tiro Libre"))
	if btn_ofensivo:
		btn_ofensivo.pressed.connect(_on_modo_seleccionado.bind("Entrenamiento Ofensivo"))
	if btn_partido_practica:
		btn_partido_practica.pressed.connect(_on_modo_seleccionado.bind("Partido de Práctica"))
	if btn_corner:
		btn_corner.pressed.connect(_on_modo_seleccionado.bind("Córner"))
	if btn_penales:
		btn_penales.pressed.connect(_on_modo_seleccionado.bind("Penales"))


## Método genérico de selección de rutina de entrenamiento.
## Para futuros modos basta con reemplazar la rama correspondiente por `change_scene_to_file()`.
func _on_modo_seleccionado(nombre_modo: String) -> void:
	match nombre_modo:
		"Tiro Libre":
			get_tree().change_scene_to_file("res://scenes/EntrenamientoTiroLibre.tscn")
		"Entrenamiento Ofensivo":
			var msg_ofensivo: String = "Próximamente entrenamiento: Entrenamiento Ofensivo"
			print(msg_ofensivo)
			_mostrar_aviso_temporal(msg_ofensivo)
		"Partido de Práctica":
			var msg_practica: String = "Próximamente entrenamiento: Partido de Práctica"
			print(msg_practica)
			_mostrar_aviso_temporal(msg_practica)
		"Córner":
			var msg_corner: String = "Próximamente entrenamiento: Córner"
			print(msg_corner)
			_mostrar_aviso_temporal(msg_corner)
		"Penales":
			var msg_penales: String = "Próximamente entrenamiento: Penales"
			print(msg_penales)
			_mostrar_aviso_temporal(msg_penales)
		_:
			var msg_generico: String = "Próximamente entrenamiento: %s" % nombre_modo
			print(msg_generico)
			_mostrar_aviso_temporal(msg_generico)


func _mostrar_aviso_temporal(texto: String) -> void:
	if panel_aviso == null or label_aviso == null:
		return
	
	label_aviso.text = texto
	panel_aviso.visible = true
	panel_aviso.modulate.a = 1.0
	
	if _tween_aviso and _tween_aviso.is_running():
		_tween_aviso.kill()
	
	_tween_aviso = create_tween()
	_tween_aviso.tween_interval(1.8)
	_tween_aviso.tween_property(panel_aviso, "modulate:a", 0.0, 0.35)
	_tween_aviso.tween_callback(func() -> void:
		panel_aviso.visible = false
	)


func _on_volver_pressed() -> void:
	if GameManager:
		GameManager.ir_al_menu_principal()
	else:
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
