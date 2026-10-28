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


static func recargar_datos() -> Dictionary:
	_datos_cacheados.clear()
	return obtener_datos()


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


static func calcular_ovr_por_posicion(posicion_tactica: String, ficha: Dictionary) -> int:
	if ficha.is_empty():
		return 75
	
	if posicion_tactica == "PORTERO":
		var gk_reflejos: float = float(ficha.get("gk_reflejos", 80.0))
		var gk_posicionamiento: float = float(ficha.get("gk_posicionamiento", 80.0))
		var gk_alcance_achique: float = float(ficha.get("gk_alcance_achique", ficha.get("gk_estirada", 80.0)))
		var gk_bloqueo_control: float = float(ficha.get("gk_bloqueo_control", ficha.get("gk_manejo", 80.0)))
		var gk_juego_pies: float = float(ficha.get("gk_juego_pies", 78.0))
		var gk_saque: float = float(ficha.get("gk_saque", 78.0))
		
		var ovr_gk: float = (
			gk_reflejos * 0.28 +
			gk_posicionamiento * 0.24 +
			gk_alcance_achique * 0.22 +
			gk_bloqueo_control * 0.14 +
			gk_juego_pies * 0.07 +
			gk_saque * 0.05
		)
		return int(round(ovr_gk))
	
	var ritmo: float = float(ficha.get("ritmo", 75.0))
	var tiro: float = float(ficha.get("tiro", 75.0))
	var pase: float = float(ficha.get("pase", 75.0))
	var regate: float = float(ficha.get("regate", 75.0))
	var defensa: float = float(ficha.get("defensa", 75.0))
	var fisico: float = float(ficha.get("fisico", 75.0))
	
	match posicion_tactica:
		"CIERRE":
			var ovr_cierre: float = (
				defensa * 0.35 +
				fisico * 0.20 +
				pase * 0.20 +
				ritmo * 0.15 +
				regate * 0.05 +
				tiro * 0.05
			)
			return int(round(ovr_cierre))
		"ALA_IZQ", "ALA_DER":
			var ovr_ala: float = (
				ritmo * 0.28 +
				regate * 0.27 +
				pase * 0.20 +
				tiro * 0.15 +
				defensa * 0.05 +
				fisico * 0.05
			)
			return int(round(ovr_ala))
		"PIVOT":
			var ovr_pivot: float = (
				tiro * 0.35 +
				fisico * 0.25 +
				regate * 0.20 +
				pase * 0.10 +
				ritmo * 0.05 +
				defensa * 0.05
			)
			return int(round(ovr_pivot))
		_:
			var ovr_gen: float = (ritmo + tiro + pase + regate + defensa + fisico) / 6.0
			return int(round(ovr_gen))


## Normalizador universal de escala técnica oficial (40 a 99) a factor 0.0 - 1.0
static func normalizar_stat(valor: float) -> float:
	return clampf((valor - 40.0) / 59.0, 0.0, 1.0)


## Retorna el color oficial de tier de estadística:
## 40-69: Bajo (Rojo) | 70-79: Promedio (Amarillo) | 80-89: Destacado (Verde) | 90-99: Élite (Cian)
static func obtener_color_stat(valor: float) -> Color:
	if valor >= 90.0:
		return Color("#1ABC9C") # Élite (Cian)
	elif valor >= 80.0:
		return Color("#2ECC71") # Destacado (Verde)
	elif valor >= 70.0:
		return Color("#F1C40F") # Promedio (Amarillo)
	else:
		return Color("#E74C3C") # Bajo (Rojo)


static func _obtener_datos_por_defecto() -> Dictionary:
	return {
		"base_datos": "Futsal_3D",
		"version": "2.0",
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
			{"id": "GK_01", "nombre": "T. Courtois", "equipo_id": "LOCAL", "dorsal": 1, "posicion_tactica": "PORTERO", "ovr": 86, "ritmo": 64, "gk_posicionamiento": 87, "gk_reflejos": 86, "gk_alcance_achique": 88, "gk_bloqueo_control": 84, "gk_juego_pies": 78, "gk_saque": 80, "gk_estirada": 88, "gk_manejo": 84, "rasgos": ["Especialista en La Cruz", "Reflejos Felinos", "Alcance Imponente", "Saque Largo"]},
			{"id": "GK_02", "nombre": "E. Martínez", "equipo_id": "VISITANTE", "dorsal": 1, "posicion_tactica": "PORTERO", "ovr": 84, "ritmo": 66, "gk_posicionamiento": 84, "gk_reflejos": 87, "gk_alcance_achique": 84, "gk_bloqueo_control": 83, "gk_juego_pies": 81, "gk_saque": 83, "gk_estirada": 84, "gk_manejo": 83, "rasgos": ["Reflejos Felinos", "Líder Defensivo", "Parador de Penaltis", "Especialista en La Cruz"]},
			{"id": "GK_03", "nombre": "J. Oblak", "equipo_id": "RESERVA", "dorsal": 13, "posicion_tactica": "PORTERO", "ovr": 85, "ritmo": 62, "gk_posicionamiento": 88, "gk_reflejos": 89, "gk_alcance_achique": 83, "gk_bloqueo_control": 87, "gk_juego_pies": 78, "gk_saque": 78, "gk_estirada": 83, "gk_manejo": 87, "rasgos": ["Manos de Hierro", "Bloqueo Seguro", "Reflejos Felinos", "Especialista en La Cruz"]},
			{"id": "GK_04", "nombre": "M. Ter Stegen", "equipo_id": "RESERVA", "dorsal": 12, "posicion_tactica": "PORTERO", "ovr": 83, "ritmo": 65, "gk_posicionamiento": 82, "gk_reflejos": 84, "gk_alcance_achique": 81, "gk_bloqueo_control": 81, "gk_juego_pies": 89, "gk_saque": 88, "gk_estirada": 81, "gk_manejo": 81, "rasgos": ["Juego de Pies Élite", "Pase al Hueco", "Reflejos Felinos", "Distribuidor Rápido"]},
			{"id": "GK_05", "nombre": "G. Donnarumma", "equipo_id": "RESERVA", "dorsal": 99, "posicion_tactica": "PORTERO", "ovr": 85, "ritmo": 67, "gk_posicionamiento": 83, "gk_reflejos": 87, "gk_alcance_achique": 89, "gk_bloqueo_control": 82, "gk_juego_pies": 76, "gk_saque": 77, "gk_estirada": 89, "gk_manejo": 82, "rasgos": ["Alcance Imponente", "Reflejos Felinos", "Especialista en La Cruz"]}
		],
		"jugadores_campo": {
			"LOCAL": [
				{"id": "LOC_CIERRE", "nombre": "C. Araujo", "dorsal": 4, "posicion_tactica": "CIERRE", "ovr": 83, "ritmo": 80, "tiro": 72, "pase": 78, "regate": 76, "defensa": 88, "fisico": 86, "sub_atributos": {"aceleracion": 78, "velocidad": 82, "finalizacion": 68, "potencia_tiro": 80, "efecto": 65, "balon_parado": 66, "pase_raso": 80, "pase_hueco": 76, "vision": 77, "control_balon": 78, "drible": 74, "equilibrio": 78, "actitud_defensiva": 89, "entrada": 87, "contacto_fisico": 89, "resistencia": 84}, "rasgos": ["Muralla Defensiva", "Entrada Limpia", "Fuerza Bruta"]},
				{"id": "LOC_ALA_IZQ", "nombre": "L. Díaz", "dorsal": 7, "posicion_tactica": "ALA_IZQ", "ovr": 85, "ritmo": 90, "tiro": 82, "pase": 82, "regate": 88, "defensa": 66, "fisico": 76, "sub_atributos": {"aceleracion": 92, "velocidad": 88, "finalizacion": 83, "potencia_tiro": 82, "efecto": 84, "balon_parado": 78, "pase_raso": 84, "pase_hueco": 82, "vision": 80, "control_balon": 89, "drible": 90, "equilibrio": 85, "actitud_defensiva": 65, "entrada": 67, "contacto_fisico": 74, "resistencia": 80}, "rasgos": ["Mago del balón", "Regate Explosivo", "Pase al Primer Toque"]},
				{"id": "LOC_ALA_DER", "nombre": "F. Valverde", "dorsal": 8, "posicion_tactica": "ALA_DER", "ovr": 85, "ritmo": 87, "tiro": 85, "pase": 86, "regate": 84, "defensa": 78, "fisico": 85, "sub_atributos": {"aceleracion": 86, "velocidad": 88, "finalizacion": 82, "potencia_tiro": 92, "efecto": 82, "balon_parado": 84, "pase_raso": 87, "pase_hueco": 86, "vision": 85, "control_balon": 85, "drible": 83, "equilibrio": 84, "actitud_defensiva": 80, "entrada": 77, "contacto_fisico": 84, "resistencia": 92}, "rasgos": ["Cañonero", "Motor Incansable", "Pase Magistral"]},
				{"id": "LOC_PIVOT", "nombre": "J. Álvarez", "dorsal": 10, "posicion_tactica": "PIVOT", "ovr": 85, "ritmo": 85, "tiro": 89, "pase": 81, "regate": 86, "defensa": 68, "fisico": 82, "sub_atributos": {"aceleracion": 87, "velocidad": 83, "finalizacion": 90, "potencia_tiro": 88, "efecto": 82, "balon_parado": 80, "pase_raso": 82, "pase_hueco": 80, "vision": 81, "control_balon": 88, "drible": 86, "equilibrio": 85, "actitud_defensiva": 70, "entrada": 67, "contacto_fisico": 80, "resistencia": 87}, "rasgos": ["Remate al primer toque", "Finalizador Letal", "Cañonero"]}
			],
			"VISITANTE": [
				{"id": "VIS_CIERRE", "nombre": "R. Dias", "dorsal": 3, "posicion_tactica": "CIERRE", "ovr": 82, "ritmo": 76, "tiro": 70, "pase": 78, "regate": 75, "defensa": 88, "fisico": 87, "sub_atributos": {"aceleracion": 74, "velocidad": 78, "finalizacion": 66, "potencia_tiro": 78, "efecto": 62, "balon_parado": 65, "pase_raso": 80, "pase_hueco": 76, "vision": 78, "control_balon": 77, "drible": 73, "equilibrio": 78, "actitud_defensiva": 90, "entrada": 87, "contacto_fisico": 88, "resistencia": 86}, "rasgos": ["Líder Defensivo", "Muralla Defensiva", "Entrada Limpia"]},
				{"id": "VIS_ALA_IZQ", "nombre": "R. Leão", "dorsal": 11, "posicion_tactica": "ALA_IZQ", "ovr": 84, "ritmo": 91, "tiro": 82, "pase": 80, "regate": 87, "defensa": 64, "fisico": 80, "sub_atributos": {"aceleracion": 90, "velocidad": 92, "finalizacion": 83, "potencia_tiro": 86, "efecto": 80, "balon_parado": 74, "pase_raso": 81, "pase_hueco": 79, "vision": 79, "control_balon": 88, "drible": 89, "equilibrio": 83, "actitud_defensiva": 62, "entrada": 65, "contacto_fisico": 82, "resistencia": 78}, "rasgos": ["Velocidad Pura", "Mago del balón", "Regate Explosivo"]},
				{"id": "VIS_ALA_DER", "nombre": "B. Silva", "dorsal": 9, "posicion_tactica": "ALA_DER", "ovr": 84, "ritmo": 82, "tiro": 81, "pase": 88, "regate": 89, "defensa": 72, "fisico": 74, "sub_atributos": {"aceleracion": 84, "velocidad": 80, "finalizacion": 81, "potencia_tiro": 78, "efecto": 86, "balon_parado": 85, "pase_raso": 90, "pase_hueco": 88, "vision": 90, "control_balon": 91, "drible": 90, "equilibrio": 87, "actitud_defensiva": 74, "entrada": 70, "contacto_fisico": 72, "resistencia": 88}, "rasgos": ["Mago del balón", "Pase Magistral", "Pase al Primer Toque"]},
				{"id": "VIS_PIVOT", "nombre": "L. Martínez", "dorsal": 10, "posicion_tactica": "PIVOT", "ovr": 84, "ritmo": 83, "tiro": 88, "pase": 79, "regate": 85, "defensa": 69, "fisico": 84, "sub_atributos": {"aceleracion": 85, "velocidad": 81, "finalizacion": 89, "potencia_tiro": 88, "efecto": 81, "balon_parado": 78, "pase_raso": 80, "pase_hueco": 78, "vision": 78, "control_balon": 86, "drible": 85, "equilibrio": 86, "actitud_defensiva": 72, "entrada": 67, "contacto_fisico": 85, "resistencia": 84}, "rasgos": ["Remate al primer toque", "Finalizador Letal", "Guerrero del Área"]}
			]
		}
	}
