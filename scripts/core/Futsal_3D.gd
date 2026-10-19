class_name Futsal_3D
extends RefCounted

## Base de datos central Futsal_3D para equipos, escudos, los 5 arqueros y estadísticas
## individuales (1-99) estilo FC Mobile / eFootball que determinan el rendimiento real in-game.

const RUTA_JSON: String = "res://data/Futsal_3D.json"

static var _datos_cacheados: Dictionary = {}


static func obtener_datos() -> Dictionary:
	if not _datos_cacheados.is_empty():
		return _datos_cacheados
	
	if FileAccess.file_exists(RUTA_JSON):
		var archivo: FileAccess = FileAccess.open(RUTA_JSON, FileAccess.READ)
		if archivo:
			var texto: String = archivo.get_as_text()
			var json: JSON = JSON.new()
			if json.parse(texto) == OK and typeof(json.data) == TYPE_DICTIONARY:
				_datos_cacheados = json.data as Dictionary
				return _datos_cacheados
	
	_datos_cacheados = _obtener_datos_por_defecto()
	return _datos_cacheados


static func obtener_info_equipo(es_local: bool) -> Dictionary:
	var datos: Dictionary = obtener_datos()
	var equipos: Dictionary = datos.get("equipos", {}) as Dictionary
	var clave: String = "LOCAL" if es_local else "VISITANTE"
	return equipos.get(clave, {}) as Dictionary


static func obtener_lista_arqueros() -> Array:
	var datos: Dictionary = obtener_datos()
	return datos.get("arqueros", []) as Array


static func obtener_arquero_equipo(es_local: bool) -> Dictionary:
	var info_eq: Dictionary = obtener_info_equipo(es_local)
	var id_titular: String = str(info_eq.get("arquero_titular_id", "GK_01" if es_local else "GK_02"))
	var arqueros: Array = obtener_lista_arqueros()
	
	for arq: Variant in arqueros:
		if typeof(arq) == TYPE_DICTIONARY:
			var d_arq: Dictionary = arq as Dictionary
			if str(d_arq.get("id", "")) == id_titular:
				return d_arq
	
	if not arqueros.is_empty():
		return arqueros[0 if es_local else mini(1, arqueros.size() - 1)] as Dictionary
	return {}


static func obtener_ficha_jugador(es_local: bool, posicion_tactica: String) -> Dictionary:
	if posicion_tactica == "PORTERO":
		return obtener_arquero_equipo(es_local)
	
	var datos: Dictionary = obtener_datos()
	var campo: Dictionary = datos.get("jugadores_campo", {}) as Dictionary
	var clave: String = "LOCAL" if es_local else "VISITANTE"
	var plantilla: Array = campo.get(clave, []) as Array
	
	for j: Variant in plantilla:
		if typeof(j) == TYPE_DICTIONARY:
			var dj: Dictionary = j as Dictionary
			if str(dj.get("posicion_tactica", "")) == posicion_tactica:
				return dj
	
	if not plantilla.is_empty():
		return plantilla[0] as Dictionary
	return {}


static func _obtener_datos_por_defecto() -> Dictionary:
	return {
		"base_datos": "Futsal_3D",
		"version": "1.0",
		"equipos": {
			"LOCAL": {
				"id": "LOCAL",
				"nombre": "Real Fútsal CF",
				"siglas": "RFC",
				"color_primario": "#D92626",
				"color_secundario": "#F2C94C",
				"color_short": "#1A1F2E",
				"color_arquero": "#19BF40",
				"arquero_titular_id": "GK_01"
			},
			"VISITANTE": {
				"id": "VISITANTE",
				"nombre": "Atlético Solar FS",
				"siglas": "ASF",
				"color_primario": "#F2D91A",
				"color_secundario": "#1F4E8C",
				"color_short": "#14243B",
				"color_arquero": "#F27319",
				"arquero_titular_id": "GK_02"
			}
		},
		"arqueros": [
			{"id": "GK_01", "nombre": "T. Courtois", "equipo_id": "LOCAL", "dorsal": 1, "posicion_tactica": "PORTERO", "ovr": 84, "ritmo": 64, "gk_estirada": 85, "gk_reflejos": 86, "gk_manejo": 82, "gk_posicionamiento": 84, "gk_saque": 80},
			{"id": "GK_02", "nombre": "E. Martínez", "equipo_id": "VISITANTE", "dorsal": 1, "posicion_tactica": "PORTERO", "ovr": 83, "ritmo": 66, "gk_estirada": 84, "gk_reflejos": 85, "gk_manejo": 80, "gk_posicionamiento": 82, "gk_saque": 83},
			{"id": "GK_03", "nombre": "J. Oblak", "equipo_id": "RESERVA", "dorsal": 13, "posicion_tactica": "PORTERO", "ovr": 85, "ritmo": 62, "gk_estirada": 83, "gk_reflejos": 87, "gk_manejo": 86, "gk_posicionamiento": 86, "gk_saque": 77},
			{"id": "GK_04", "nombre": "M. Ter Stegen", "equipo_id": "RESERVA", "dorsal": 12, "posicion_tactica": "PORTERO", "ovr": 82, "ritmo": 65, "gk_estirada": 81, "gk_reflejos": 84, "gk_manejo": 79, "gk_posicionamiento": 81, "gk_saque": 88},
			{"id": "GK_05", "nombre": "G. Donnarumma", "equipo_id": "RESERVA", "dorsal": 99, "posicion_tactica": "PORTERO", "ovr": 83, "ritmo": 67, "gk_estirada": 86, "gk_reflejos": 86, "gk_manejo": 78, "gk_posicionamiento": 80, "gk_saque": 76}
		],
		"jugadores_campo": {
			"LOCAL": [
				{"id": "LOC_CIERRE", "nombre": "C. Araujo", "dorsal": 4, "posicion_tactica": "CIERRE", "ovr": 82, "ritmo": 79, "tiro": 74, "pase": 80, "regate": 78, "defensa": 87, "fisico": 85},
				{"id": "LOC_ALA_IZQ", "nombre": "L. Díaz", "dorsal": 7, "posicion_tactica": "ALA_IZQ", "ovr": 84, "ritmo": 89, "tiro": 81, "pase": 83, "regate": 87, "defensa": 68, "fisico": 76},
				{"id": "LOC_ALA_DER", "nombre": "F. Valverde", "dorsal": 8, "posicion_tactica": "ALA_DER", "ovr": 85, "ritmo": 86, "tiro": 84, "pase": 86, "regate": 84, "defensa": 78, "fisico": 84},
				{"id": "LOC_PIVOT", "nombre": "J. Álvarez", "dorsal": 10, "posicion_tactica": "PIVOT", "ovr": 86, "ritmo": 85, "tiro": 89, "pase": 81, "regate": 87, "defensa": 70, "fisico": 82}
			],
			"VISITANTE": [
				{"id": "VIS_CIERRE", "nombre": "R. Dias", "dorsal": 3, "posicion_tactica": "CIERRE", "ovr": 82, "ritmo": 77, "tiro": 72, "pase": 79, "regate": 76, "defensa": 86, "fisico": 86},
				{"id": "VIS_ALA_IZQ", "nombre": "R. Leão", "dorsal": 11, "posicion_tactica": "ALA_IZQ", "ovr": 84, "ritmo": 88, "tiro": 80, "pase": 81, "regate": 86, "defensa": 65, "fisico": 80},
				{"id": "VIS_ALA_DER", "nombre": "B. Silva", "dorsal": 9, "posicion_tactica": "ALA_DER", "ovr": 84, "ritmo": 83, "tiro": 81, "pase": 87, "regate": 88, "defensa": 72, "fisico": 74},
				{"id": "VIS_PIVOT", "nombre": "L. Martínez", "dorsal": 10, "posicion_tactica": "PIVOT", "ovr": 85, "ritmo": 83, "tiro": 88, "pase": 79, "regate": 85, "defensa": 69, "fisico": 83}
			]
		}
	}
