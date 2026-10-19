extends Node

## Singleton global para persistencia de estado, economía, marcador, reloj neto de futsal (2 tiempos),
## acumulación de faltas (Doble Penalti a la 6ª falta) y tiempos muertos por periodo.

signal marcador_actualizado(goles_local: int, goles_visitante: int)
signal tiempo_actualizado(minutos: int, segundos: int)
signal faltas_actualizadas(faltas_local: int, faltas_visitante: int)
signal periodo_cambiado(nuevo_periodo: int)
signal fin_primer_tiempo()
signal partido_finalizado(goles_local: int, goles_visitante: int)

@export_group("Economía del Jugador")
var monedas: int = 15400
var gemas: int = 750

@export_group("Estado del Partido y Reglamento Futsal")
var goles_local: int = 0
var goles_visitante: int = 0
var periodo_actual: int = 1 ## 1 = Primer Tiempo, 2 = Segundo Tiempo
var duracion_periodo_segundos: float = 1200.0 ## 20:00 minutos reglamentarios de reloj neto por tiempo
var duracion_partido_segundos: float = 2400.0
var tiempo_restante: float = 1200.0
var partido_en_curso: bool = false
var reloj_neto_activo: bool = false ## Solo avanza cuando el balón está en juego (EN_JUEGO)
var dificultad_cpu: String = "MEDIA"

# Acumulación de faltas por tiempo (6ª falta = Doble Penalti desde 10m)
var faltas_local: int = 0
var faltas_visitante: int = 0

# Derecho a 1 Tiempo Muerto por tiempo para cada equipo
var tiempo_muerto_usado_local: bool = false
var tiempo_muerto_usado_visitante: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if partido_en_curso and reloj_neto_activo and not get_tree().paused:
		tiempo_restante -= delta
		if tiempo_restante <= 0.0:
			tiempo_restante = 0.0
			reloj_neto_activo = false
			if periodo_actual == 1:
				fin_primer_tiempo.emit()
			else:
				partido_en_curso = false
				partido_finalizado.emit(goles_local, goles_visitante)
		
		var mins: int = int(tiempo_restante) / 60
		var segs: int = int(tiempo_restante) % 60
		tiempo_actualizado.emit(mins, segs)


## Inicia o resetea el reloj neto (20:00), faltas y marcador para un nuevo partido (pausado hasta el saque de centro)
func iniciar_partido() -> void:
	goles_local = 0
	goles_visitante = 0
	periodo_actual = 1
	tiempo_restante = duracion_periodo_segundos
	faltas_local = 0
	faltas_visitante = 0
	tiempo_muerto_usado_local = false
	tiempo_muerto_usado_visitante = false
	partido_en_curso = true
	reloj_neto_activo = false
	get_tree().paused = false
	
	marcador_actualizado.emit(goles_local, goles_visitante)
	faltas_actualizadas.emit(faltas_local, faltas_visitante)
	periodo_cambiado.emit(periodo_actual)
	
	var mins: int = int(tiempo_restante) / 60
	var segs: int = int(tiempo_restante) % 60
	tiempo_actualizado.emit(mins, segs)


## Avanza al segundo tiempo reiniciando el reloj del periodo (20:00), faltas acumuladas y tiempos muertos
func iniciar_segundo_tiempo() -> void:
	periodo_actual = 2
	tiempo_restante = duracion_periodo_segundos
	faltas_local = 0
	faltas_visitante = 0
	tiempo_muerto_usado_local = false
	tiempo_muerto_usado_visitante = false
	reloj_neto_activo = false
	
	faltas_actualizadas.emit(faltas_local, faltas_visitante)
	periodo_cambiado.emit(periodo_actual)
	var mins: int = int(tiempo_restante) / 60
	var segs: int = int(tiempo_restante) % 60
	tiempo_actualizado.emit(mins, segs)


## Verifica si el equipo (0 = Local, 1 = Visitante) aún dispone de su tiempo muerto en el periodo actual
func puede_pedir_tiempo_muerto(equipo_solicitante: int) -> bool:
	if not partido_en_curso:
		return false
	if equipo_solicitante == 0:
		return not tiempo_muerto_usado_local
	return not tiempo_muerto_usado_visitante


## Marca como utilizado el tiempo muerto del equipo en el periodo actual
func usar_tiempo_muerto(equipo_solicitante: int) -> void:
	if equipo_solicitante == 0:
		tiempo_muerto_usado_local = true
	else:
		tiempo_muerto_usado_visitante = true


## Registra una falta acumulada en el periodo actual y devuelve el total acumulado de ese equipo
func registrar_falta_equipo(equipo_infractor: int) -> int:
	if equipo_infractor == 0:
		faltas_local += 1
		faltas_actualizadas.emit(faltas_local, faltas_visitante)
		return faltas_local
	else:
		faltas_visitante += 1
		faltas_actualizadas.emit(faltas_local, faltas_visitante)
		return faltas_visitante


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
	reloj_neto_activo = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")

