class_name Cancha3D
extends Node3D

## Controlador de la pista de juego 3D, gestión de goles, saques de banda reglamentarios,
## saques de esquina (córners) y saques de meta según la normativa de fútbol sala.
## Delega las reanudaciones y flujo de juego a GestorPartido.

@onready var balon: Balon3D = $Balon3D
@onready var area_gol_izq: Area3D = $AreaGolIzquierda
@onready var area_gol_der: Area3D = $AreaGolDerecha
@onready var gestor: GestorPartido = $GestorPartido
@onready var contenedor_jugadores: Node3D = $Jugadores


func _ready() -> void:
	_inicializar_uniformes_equipos()
	if area_gol_izq:
		area_gol_izq.body_entered.connect(_on_gol_arco_izquierdo)
	if area_gol_der:
		area_gol_der.body_entered.connect(_on_gol_arco_derecho)


## Verifica y asigna la paleta de materiales StandardMaterial3D a los 10 jugadores en cancha:
## - Equipo Local (RFC): Camiseta Roja (#D92626), short Negro (#1A1F2E) | Arquero: Verde Esmeralda (#19BF40)
## - Equipo Visitante (ASF): Camiseta Amarilla (#F2D91A), short Azul Marino (#14243B) | Arquero: Naranja Coral (#F27319)
func _inicializar_uniformes_equipos() -> void:
	if contenedor_jugadores == null:
		return
	
	for nodo: Node in contenedor_jugadores.get_children():
		var jugador: Jugador3D = nodo as Jugador3D
		if jugador == null:
			continue
		
		var id_equipo: int = int(jugador.equipo)
		if jugador.name.begins_with("Vis_"):
			id_equipo = 1
		elif jugador.name.begins_with("Local_"):
			id_equipo = 0
		
		jugador.aplicar_uniforme_equipo(id_equipo)


func _physics_process(_delta: float) -> void:
	if gestor and gestor.estado != GestorPartido.EstadoPartido.EN_JUEGO:
		return
	if balon == null or not is_instance_valid(balon):
		return
	if balon.esta_fuera_de_juego:
		return
	
	var pos: Vector3 = balon.global_position
	
	# 1. Comprobación de líneas de banda laterales (|Z| > 10.08 m dentro del largo |X| <= 20.0 m)
	if abs(pos.z) > 10.08 and abs(pos.x) <= 20.0:
		_procesar_saque_de_banda(pos)
		return
	
	# 2. Comprobación de líneas de fondo / meta (|X| > 20.08 m y fuera de la boca del arco de 3.7m |Z| > 1.90 m)
	if abs(pos.x) > 20.08 and abs(pos.z) > 1.90:
		_procesar_saque_fondo(pos)
		return


func _procesar_saque_de_banda(pos_salida: Vector3) -> void:
	# El saque corresponde al equipo rival del que dio el último toque
	var equipo_favorecido: int = 1 if balon.ultimo_toque_equipo == 0 else 0
	var info_eq: Dictionary = Futsal_3D.obtener_info_equipo(equipo_favorecido == 0)
	var nombre_equipo: String = str(info_eq.get("siglas", "LOCAL" if equipo_favorecido == 0 else "VIS"))
	_emitir_anuncio("¡SAQUE DE BANDA (%s) — APUNTA Y PASA!" % nombre_equipo)
	
	# Colocar el balón sobre la línea de banda con margen seguro interior (Z = +/- 9.65)
	var z_linea: float = 9.65 if pos_salida.z > 0.0 else -9.65
	var x_linea: float = clampf(pos_salida.x, -18.8, 18.8)
	var pos_reanudacion: Vector3 = Vector3(x_linea, 0.25, z_linea)
	
	if gestor:
		gestor.iniciar_reanudacion(GestorPartido.EstadoPartido.SAQUE_BANDA, pos_reanudacion, equipo_favorecido)


func _procesar_saque_fondo(pos_salida: Vector3) -> void:
	var salio_por_arco_local: bool = pos_salida.x < 0.0
	var ultimo_toque: int = balon.ultimo_toque_equipo
	var siglas_loc: String = str(Futsal_3D.obtener_info_equipo(true).get("siglas", "RFC"))
	var siglas_vis: String = str(Futsal_3D.obtener_info_equipo(false).get("siglas", "ASF"))
	
	if salio_por_arco_local:
		if ultimo_toque == 1:
			# Último toque de visitante (atacante) -> SAQUE DE META LOCAL
			_emitir_anuncio("¡SAQUE DE META (%s)!" % siglas_loc)
			var pos_meta: Vector3 = Vector3(-17.8, 0.25, 0.0)
			if gestor:
				gestor.iniciar_reanudacion(GestorPartido.EstadoPartido.SAQUE_META, pos_meta, 0)
			return
		else:
			# Último toque de local (defensor) -> CÓRNER PARA VISITANTE
			_emitir_anuncio("¡CÓRNER (%s)!" % siglas_vis)
			var z_corner: float = 9.4 if pos_salida.z > 0.0 else -9.4
			var pos_corner: Vector3 = Vector3(-19.4, 0.25, z_corner)
			if gestor:
				gestor.iniciar_reanudacion(GestorPartido.EstadoPartido.SAQUE_ESQUINA, pos_corner, 1)
	else:
		if ultimo_toque == 0:
			# Último toque de local (atacante) -> SAQUE DE META VISITANTE
			_emitir_anuncio("¡SAQUE DE META (%s)!" % siglas_vis)
			var pos_meta: Vector3 = Vector3(17.8, 0.25, 0.0)
			if gestor:
				gestor.iniciar_reanudacion(GestorPartido.EstadoPartido.SAQUE_META, pos_meta, 1)
			return
		else:
			# Último toque de visitante (defensor) -> CÓRNER PARA LOCAL
			_emitir_anuncio("¡CÓRNER (%s)!" % siglas_loc)
			var z_corner: float = 9.4 if pos_salida.z > 0.0 else -9.4
			var pos_corner: Vector3 = Vector3(19.4, 0.25, z_corner)
			if gestor:
				gestor.iniciar_reanudacion(GestorPartido.EstadoPartido.SAQUE_ESQUINA, pos_corner, 0)


func _emitir_anuncio(texto: String) -> void:
	var hud: HUDPartido = get_tree().get_first_node_in_group("hud_partido") as HUDPartido
	if hud and is_instance_valid(hud):
		hud.mostrar_anuncio(texto)


func _on_gol_arco_izquierdo(body: Node3D) -> void:
	if gestor and gestor.estado != GestorPartido.EstadoPartido.EN_JUEGO:
		return
	if body != balon:
		return
	if balon.esta_siendo_conducido() and balon.portador_actual is Jugador3D:
		var portador: Jugador3D = balon.portador_actual as Jugador3D
		if portador and (portador.posicion_tactica == "PORTERO" or portador.tiene_balon_en_manos):
			return
	if gestor and not gestor.validar_y_procesar_gol(1):
		return
	
	var nombre_vis: String = str(Futsal_3D.obtener_info_equipo(false).get("nombre", "VISITANTE")).to_upper()
	_emitir_anuncio("¡¡GOOOOL DE %s!!" % nombre_vis)
	if GameManager:
		GameManager.anotar_gol_visitante()
	if gestor:
		gestor.iniciar_gol(1)


func _on_gol_arco_derecho(body: Node3D) -> void:
	if gestor and gestor.estado != GestorPartido.EstadoPartido.EN_JUEGO:
		return
	if body != balon:
		return
	if balon.esta_siendo_conducido() and balon.portador_actual is Jugador3D:
		var portador: Jugador3D = balon.portador_actual as Jugador3D
		if portador and (portador.posicion_tactica == "PORTERO" or portador.tiene_balon_en_manos):
			return
	if gestor and not gestor.validar_y_procesar_gol(0):
		return
	
	var nombre_loc: String = str(Futsal_3D.obtener_info_equipo(true).get("nombre", "LOCAL")).to_upper()
	_emitir_anuncio("¡¡GOOOOL DE %s!!" % nombre_loc)
	if GameManager:
		GameManager.anotar_gol_local()
	if gestor:
		gestor.iniciar_gol(0)

