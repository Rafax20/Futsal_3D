class_name MainMenu
extends Control

## Menú Principal estilo FC Mobile con mosaico de tarjetas de eventos,
## barra superior de economía (Monedas y Gemas) y navegación fluida.

@onready var label_monedas: Label = $MargenSuperior/BarraSuperior/ContenedorEconomia/PanelMonedas/HBox/LabelMonedas
@onready var label_gemas: Label = $MargenSuperior/BarraSuperior/ContenedorEconomia/PanelGemas/HBox/LabelGemas

# Botones y tarjetas
@onready var btn_jugar_destacado: Button = $MargenPrincipal/MosaicoContenedor/TarjetaPartidoRapido/VBox/BotonJugar
@onready var btn_entrenamiento: Button = get_node_or_null("MargenPrincipal/MosaicoContenedor/TarjetaPartidoRapido/VBox/BotonEntrenamiento") as Button
@onready var btn_tarjeta_partido: Button = $MargenPrincipal/MosaicoContenedor/TarjetaPartidoRapido/BotonAccesoRapido
@onready var btn_alineacion: Button = $MargenPrincipal/MosaicoContenedor/ColumnaSecundaria/TarjetaAlineacion/VBox/BotonAlineacion
@onready var btn_tienda: Button = $MargenPrincipal/MosaicoContenedor/ColumnaSecundaria/FilaInferior/TarjetaTienda/VBox/BotonTienda
@onready var btn_online: Button = $MargenPrincipal/MosaicoContenedor/ColumnaSecundaria/FilaInferior/TarjetaOnline/VBox/BotonOnline

# Modal de información para secciones secundarias
@onready var modal_info: ColorRect = $ModalInfo
@onready var label_titulo_modal: Label = $ModalInfo/PanelModal/VBox/TituloModal
@onready var label_desc_modal: Label = $ModalInfo/PanelModal/VBox/DescModal
@onready var btn_cerrar_modal: Button = $ModalInfo/PanelModal/VBox/BotonCerrarModal


func _ready() -> void:
	_actualizar_indicadores_economia()
	_conectar_eventos()
	modal_info.visible = false


func _actualizar_indicadores_economia() -> void:
	if GameManager:
		label_monedas.text = "%s" % _formatear_numero(GameManager.monedas)
		label_gemas.text = "%s" % _formatear_numero(GameManager.gemas)


func _conectar_eventos() -> void:
	if btn_jugar_destacado:
		btn_jugar_destacado.pressed.connect(_on_iniciar_partido_pressed)
	if btn_entrenamiento:
		btn_entrenamiento.pressed.connect(_on_entrenamiento_pressed)
	if btn_tarjeta_partido:
		btn_tarjeta_partido.pressed.connect(_on_iniciar_partido_pressed)
	
	if btn_alineacion:
		btn_alineacion.pressed.connect(_on_alineacion_pressed)
	if btn_tienda:
		btn_tienda.pressed.connect(_on_tienda_pressed)
	if btn_online:
		btn_online.pressed.connect(_on_online_pressed)
	
	if btn_cerrar_modal:
		btn_cerrar_modal.pressed.connect(_on_cerrar_modal_pressed)


func _on_iniciar_partido_pressed() -> void:
	if GameManager:
		GameManager.cargar_partido()
	else:
		get_tree().change_scene_to_file("res://scenes/Cancha3D.tscn")


func _on_entrenamiento_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/MenuEntrenamiento.tscn")


func _on_alineacion_pressed() -> void:
	_mostrar_modal(
		"MI EQUIPO - ALINEACIÓN 1-2-1",
		"Esquema Rombo Futsal Oficial:\n\n• Portero: D1 Reflejos Rápidos\n• Cierre: D4 Anticipación y Despeje\n• Ala Izquierda: D7 Desborde y Velocidad\n• Ala Derecha: D8 Pase Preciso\n• Pívot: D10 Goleador Titular (Controlado por ti)\n\n¡Tus 5 jugadores están listos en pista!"
	)


func _on_tienda_pressed() -> void:
	_mostrar_modal(
		"TIENDA Y MERCADO DE FUTSAL",
		"Artículos Disponibles:\n\n• Balón Penalty Max 1000 Pro (3,500 🪙)\n• Zapatillas de Pista Indoor Pro (6,000 🪙)\n• Kit Uniforme Clásico de Futsal (250 💎)\n\n(Catálogo completo disponible en la próxima actualización)."
	)


func _on_online_pressed() -> void:
	_mostrar_modal(
		"EN LÍNEA / EVENTOS DE TORNEO",
		"Modo Multijugador y Torneo Relámpago:\n\n• Emparejamiento PvP 5v5 con bajo lag.\n• Temporada de División de Ascenso.\n\n¡Próximamente disponible en la fase multijugador!"
	)


func _mostrar_modal(titulo: String, descripcion: String) -> void:
	label_titulo_modal.text = titulo
	label_desc_modal.text = descripcion
	modal_info.visible = true


func _on_cerrar_modal_pressed() -> void:
	modal_info.visible = false


func _formatear_numero(n: int) -> String:
	var texto: String = str(n)
	var longitud: int = texto.length()
	if longitud <= 3:
		return texto
	
	var resultado: String = ""
	var contador: int = 0
	for i: int in range(longitud - 1, -1, -1):
		resultado = texto[i] + resultado
		contador += 1
		if contador % 3 == 0 and i > 0:
			resultado = "," + resultado
	return resultado
