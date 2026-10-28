class_name ReplayBuffer
extends RefCounted

## Ring Buffer circular ligero para grabar y reproducir repeticiones en tiempo real
## (últimos 2.0s a 30 FPS) de jugadores y balón en faltas, penaltis y goles.

class SnapshotJugador:
	var nodo: Jugador3D = null
	var pos: Vector3 = Vector3.ZERO
	var rot_y: float = 0.0
	var vel: Vector3 = Vector3.ZERO

class SnapshotFrame:
	var tiempo: float = 0.0
	var pos_balon: Vector3 = Vector3.ZERO
	var rot_balon: Basis = Basis.IDENTITY
	var vel_balon: Vector3 = Vector3.ZERO
	var jugadores: Array[SnapshotJugador] = []

const CAPACIDAD_SAMPLES: int = 70 # ~2.33 segundos a 30 Hz
const INTERVALO_MUESTREO: float = 1.0 / 30.0 # ~0.0333 segundos

var _buffer: Array[SnapshotFrame] = []
var _head: int = 0
var _cantidad: int = 0
var _acumulador_tiempo: float = 0.0
var _tiempo_global: float = 0.0
var _grabando: bool = true


func _init() -> void:
	_buffer.resize(CAPACIDAD_SAMPLES)


## Reinicia el buffer de repetición
func reiniciar() -> void:
	_head = 0
	_cantidad = 0
	_acumulador_tiempo = 0.0
	_tiempo_global = 0.0


func pausar_grabacion() -> void:
	_grabando = false


func reanudar_grabacion() -> void:
	_grabando = true


func esta_grabando() -> bool:
	return _grabando


## Registra un frame en el ring buffer circular si se alcanzó el intervalo de muestreo
func registrar_frame(delta: float, balon: Node3D, jugadores: Array) -> void:
	if not _grabando or balon == null:
		return
	
	_acumulador_tiempo += delta
	_tiempo_global += delta
	
	if _acumulador_tiempo < INTERVALO_MUESTREO:
		return
	
	_acumulador_tiempo = fmod(_acumulador_tiempo, INTERVALO_MUESTREO)
	
	var frame: SnapshotFrame = SnapshotFrame.new()
	frame.tiempo = _tiempo_global
	frame.pos_balon = balon.global_position
	frame.rot_balon = balon.global_transform.basis
	if balon is RigidBody3D:
		frame.vel_balon = (balon as RigidBody3D).linear_velocity
	
	for n: Node in jugadores:
		var j: Jugador3D = n as Jugador3D
		if j and is_instance_valid(j):
			var sj: SnapshotJugador = SnapshotJugador.new()
			sj.nodo = j
			sj.pos = j.global_position
			sj.rot_y = j.rotation.y
			sj.vel = j.velocity
			frame.jugadores.append(sj)
	
	_buffer[_head] = frame
	_head = (_head + 1) % CAPACIDAD_SAMPLES
	if _cantidad < CAPACIDAD_SAMPLES:
		_cantidad += 1


## Retorna los frames ordenados cronológicamente correspondientes a la duración solicitada
func obtener_frames(duracion_solicitada: float = 2.0) -> Array[SnapshotFrame]:
	var resultado: Array[SnapshotFrame] = []
	if _cantidad == 0:
		return resultado
	
	var samples_necesarios: int = mini(_cantidad, int(ceil(duracion_solicitada / INTERVALO_MUESTREO)))
	var idx_inicial: int = (_head - samples_necesarios + CAPACIDAD_SAMPLES) % CAPACIDAD_SAMPLES
	
	for i: int in range(samples_necesarios):
		var idx: int = (idx_inicial + i) % CAPACIDAD_SAMPLES
		var sf: SnapshotFrame = _buffer[idx]
		if sf != null:
			resultado.append(sf)
	
	return resultado


## Aplica las transformaciones de un frame de repetición a los nodos físicos de la escena
func aplicar_snapshot(frame: SnapshotFrame, balon: Node3D) -> void:
	if frame == null:
		return
	
	if balon and is_instance_valid(balon):
		balon.global_position = frame.pos_balon
		balon.global_transform.basis = frame.rot_balon
		if balon is RigidBody3D:
			(balon as RigidBody3D).linear_velocity = frame.vel_balon
			(balon as RigidBody3D).angular_velocity = Vector3.ZERO
	
	for sj: SnapshotJugador in frame.jugadores:
		if sj.nodo and is_instance_valid(sj.nodo):
			sj.nodo.global_position = sj.pos
			sj.nodo.rotation.y = sj.rot_y
			sj.nodo.velocity = sj.vel
