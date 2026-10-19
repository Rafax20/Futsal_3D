extends Node

## Singleton global para persistencia de estado, economía, marcador y navegación de escenas.

signal marcador_actualizado(goles_local: int, goles_visitante: int)
signal tiempo_actualizado(minutos: int, segundos: int)
signal partido_finalizado(goles_local: int, goles_visitante: int)

@export_group("Economía del Jugador")
var monedas: int = 15400
var gemas: int = 750

@export_group("Estado del Partido")
var goles_local: int = 0
var goles_visitante: int = 0
var duracion_partido_segundos: float = 180.0 ## 3 minutos reglamentarios en versión móvil
var tiempo_restante: float = 180.0
var partido_en_curso: bool = false
var dificultad_cpu: String = "MEDIA"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if partido_en_curso and not get_tree().paused:
		tiempo_restante -= delta
		if tiempo_restante <= 0.0:
			tiempo_restante = 0.0
			partido_en_curso = false
			partido_finalizado.emit(goles_local, goles_visitante)
		
		var mins: int = int(tiempo_restante) / 60
		var segs: int = int(tiempo_restante) % 60
		tiempo_actualizado.emit(mins, segs)


## Inicia o resetea el reloj y marcador para un nuevo partido
func iniciar_partido() -> void:
	goles_local = 0
	goles_visitante = 0
	tiempo_restante = duracion_partido_segundos
	partido_en_curso = true
	get_tree().paused = false
	marcador_actualizado.emit(goles_local, goles_visitante)
	
	var mins: int = int(tiempo_restante) / 60
	var segs: int = int(tiempo_restante) % 60
	tiempo_actualizado.emit(mins, segs)


func anotar_gol_local() -> void:
	goles_local += 1
	marcador_actualizado.emit(goles_local, goles_visitante)


func anotar_gol_visitante() -> void:
	goles_visitante += 1
	marcador_actualizado.emit(goles_local, goles_visitante)


func obtener_tiempo_formateado() -> String:
	var mins: int = int(tiempo_restante) / 60
	var segs: int = int(tiempo_restante) % 60
	return "%02d:%02d" % [mins, segs]


func cargar_partido() -> void:
	iniciar_partido()
	get_tree().change_scene_to_file("res://scenes/Cancha3D.tscn")


func reiniciar_partido() -> void:
	iniciar_partido()
	get_tree().reload_current_scene()


func ir_al_menu_principal() -> void:
	partido_en_curso = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
