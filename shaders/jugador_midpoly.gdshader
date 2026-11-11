shader_type spatial;
// Pipeline PBR Ligero para Móviles (Android / Vulkan Mobile / GLES3 Compatibility).
// - Renderizado estrictamente opaco (Early-Z habilitado) con difusión Burley y especular Schlick-GGX.
// - Sin cálculos costosos de Subsurface Scattering (SSS), refracción, clearcoat ni alpha-blending.
// - Soporta un único Texture Atlas 2048x2048 (o 1024x1024) compartido por equipo (1 solo lote / Draw Call)
//   y diferenciación por instancia (dorsal, variante de piel/pelo y zona UV) sin duplicar el Material.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
// 1. TEXTURE ATLAS COMPARTIDO POR EQUIPO (2048x2048 / 1024x1024)
//    Cuadrante 1 (UV [0.0..0.5, 0.0..0.5]): Variantes de caras, piel y peinados.
//    Cuadrante 2 (UV [0.5..1.0, 0.0..0.5]): Camiseta frontal/trasera y dorsal.
//    Cuadrante 3 (UV [0.0..0.5, 0.5..1.0]): Shorts, medias y guantes.
//    Cuadrante 4 (UV [0.5..1.0, 0.5..1.0]): Zapatillas de futsal y suela indoor.
// ============================================================================
group_uniforms TextureAtlas;
uniform sampler2D textura_atlas_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D textura_atlas_normal : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D textura_atlas_orm : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform float mezcla_textura_atlas : hint_range(0.0, 1.0, 0.05) = 0.0;

// ============================================================================
// 2. PALETA DINÁMICA DE EQUIPO (UNIFORME COMPARTIDO POR LOTE)
// ============================================================================
group_uniforms PaletaEquipo;
uniform vec4 color_camiseta : source_color = vec4(0.85, 0.15, 0.15, 1.0);
uniform vec4 color_secundario : source_color = vec4(0.95, 0.80, 0.20, 1.0);
uniform vec4 color_short : source_color = vec4(0.10, 0.12, 0.18, 1.0);
uniform vec4 color_medias : source_color = vec4(0.85, 0.15, 0.15, 1.0);
uniform vec4 color_botines : source_color = vec4(0.12, 0.14, 0.18, 1.0);
uniform vec4 color_piel_base : source_color = vec4(0.88, 0.72, 0.58, 1.0);
uniform vec4 color_pelo_base : source_color = vec4(0.12, 0.09, 0.08, 1.0);

// ============================================================================
// 3. PARÁMETROS PBR COMPACTOS (RELIEVE NORMAL MAP, RUGOSIDAD Y METÁLICO)
// ============================================================================
group_uniforms ParametrosPBR;
uniform float intensidad_normal : hint_range(0.0, 2.0, 0.05) = 0.85;
uniform float rugosidad_tela : hint_range(0.0, 1.0, 0.05) = 0.58;
uniform float rugosidad_piel : hint_range(0.0, 1.0, 0.05) = 0.50;
uniform float rugosidad_botin : hint_range(0.0, 1.0, 0.05) = 0.30;
uniform float metalico_base : hint_range(0.0, 1.0, 0.05) = 0.04;
uniform float metalico_escudo : hint_range(0.0, 1.0, 0.05) = 0.35;

// ============================================================================
// 4. DORSAL SUPERPUESTO EN ESPALDA (CUADRANTE 2)
// ============================================================================
group_uniforms DorsalConfig;
uniform vec4 color_dorsal : source_color = vec4(0.98, 0.98, 0.98, 1.0);
// Región UV trasera dentro del Cuadrante 2 (x_min, y_min, ancho, alto)
uniform vec4 region_uv_dorsal = vec4(0.70, 0.14, 0.16, 0.20);

// ============================================================================
// 5. PARÁMETROS POR INSTANCIA (SIN DUPLICAR EL RECURSO MATERIAL)
//    Permiten diferenciar dorsal, variante de piel/pelo y sub-malla manteniendo
//    el batching de los 5 jugadores del equipo en un único ShaderMaterial.
// ============================================================================
// id_zona_malla:
//   0 = Detección automática por cuadrante UV (Malla unificada Mid-Poly con UVs en Atlas)
//   1 = Piel (Cabeza, Cuello, Brazos, Piernas)
//   2 = Pelo (Cabello estilizado)
//   3 = Camiseta y Mangas (Color primario)
//   4 = Escudo y Detalles (Color secundario)
//   5 = Shorts y Muslos (Color pantalón)
//   6 = Medias (Color medias)
//   7 = Botines / Guantes
instance uniform int id_zona_malla = 0;
instance uniform int dorsal_jugador = 10;
instance uniform int variante_aspecto = 0;

// Renderizador procedural ultraligero de dígitos 7-segmentos para dorsales en el Atlas UV
float _segmento_dorsal(vec2 uv, vec2 p_min, vec2 p_max) {
	vec2 d = step(p_min, uv) - step(p_max, uv);
	return d.x * d.y;
}

float _dibujar_digito_7seg(vec2 uv, int digito) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		return 0.0;
	}
	// Segmentos: A(arriba), B(sup-der), C(inf-der), D(abajo), E(inf-izq), F(sup-izq), G(centro)
	float seg_a = _segmento_dorsal(uv, vec2(0.15, 0.05), vec2(0.85, 0.18));
	float seg_d = _segmento_dorsal(uv, vec2(0.15, 0.82), vec2(0.85, 0.95));
	float seg_g = _segmento_dorsal(uv, vec2(0.15, 0.44), vec2(0.85, 0.56));
	float seg_f = _segmento_dorsal(uv, vec2(0.12, 0.08), vec2(0.28, 0.50));
	float seg_e = _segmento_dorsal(uv, vec2(0.12, 0.50), vec2(0.28, 0.92));
	float seg_b = _segmento_dorsal(uv, vec2(0.72, 0.08), vec2(0.88, 0.50));
	float seg_c = _segmento_dorsal(uv, vec2(0.72, 0.50), vec2(0.88, 0.92));

	float m = 0.0;
	if (digito == 0) { m = seg_a + seg_b + seg_c + seg_d + seg_e + seg_f; }
	else if (digito == 1) { m = seg_b + seg_c; }
	else if (digito == 2) { m = seg_a + seg_b + seg_g + seg_e + seg_d; }
	else if (digito == 3) { m = seg_a + seg_b + seg_g + seg_c + seg_d; }
	else if (digito == 4) { m = seg_f + seg_g + seg_b + seg_c; }
	else if (digito == 5) { m = seg_a + seg_f + seg_g + seg_c + seg_d; }
	else if (digito == 6) { m = seg_a + seg_f + seg_e + seg_d + seg_c + seg_g; }
	else if (digito == 7) { m = seg_a + seg_b + seg_c; }
	else if (digito == 8) { m = seg_a + seg_b + seg_c + seg_d + seg_e + seg_f + seg_g; }
	else if (digito == 9) { m = seg_a + seg_b + seg_c + seg_d + seg_f + seg_g; }
	return clamp(m, 0.0, 1.0);
}

float _calcular_mascara_dorsal(vec2 uv_actual, int numero) {
	if (numero <= 0) {
		return 0.0;
	}
	vec2 uv_rel = (uv_actual - region_uv_dorsal.xy) / max(vec2(0.001), region_uv_dorsal.zw);
	if (uv_rel.x < 0.0 || uv_rel.x > 1.0 || uv_rel.y < 0.0 || uv_rel.y > 1.0) {
		return 0.0;
	}
	int num_clamp = clamp(numero, 1, 99);
	if (num_clamp < 10) {
		vec2 uv_unico = vec2((uv_rel.x - 0.22) / 0.56, uv_rel.y);
		return _dibujar_digito_7seg(uv_unico, num_clamp);
	} else {
		int decenas = num_clamp / 10;
		int unidades = num_clamp - (decenas * 10);
		vec2 uv_dec = vec2(uv_rel.x / 0.46, uv_rel.y);
		vec2 uv_uni = vec2((uv_rel.x - 0.54) / 0.46, uv_rel.y);
		return max(_dibujar_digito_7seg(uv_dec, decenas), _dibujar_digito_7seg(uv_uni, unidades));
	}
}

void fragment() {
	// 1. Determinar zona de material: por override de sub-malla o por Cuadrante UV del Atlas 2048x2048
	int zona = id_zona_malla;
	if (zona == 0) {
		bool mitad_derecha = (UV.x >= 0.5);
		bool mitad_inferior = (UV.y >= 0.5);
		if (!mitad_derecha && !mitad_inferior) {
			// Cuadrante 1 (Superior Izquierdo): Cara / Piel / Pelo
			zona = (UV.y < 0.35) ? 1 : 2;
		} else if (mitad_derecha && !mitad_inferior) {
			// Cuadrante 2 (Superior Derecho): Camiseta frontal/trasera
			zona = 3;
		} else if (!mitad_derecha && mitad_inferior) {
			// Cuadrante 3 (Inferior Izquierdo): Shorts (arriba) y Medias (abajo)
			zona = (UV.y < 0.78) ? 5 : 6;
		} else {
			// Cuadrante 4 (Inferior Derecho): Zapatillas de futsal y suela
			zona = 7;
		}
	}

	// 2. Variación sutil de tono de piel y cabello según `variante_aspecto` (0..3) sin romper el batching
	float factor_var = float(clamp(variante_aspecto, 0, 3)) * 0.08;
	vec3 piel_ajustada = color_piel_base.rgb * (1.0 - factor_var);
	vec3 pelo_ajustado = mix(color_pelo_base.rgb, vec3(0.32, 0.22, 0.12), factor_var * 1.4);

	// 3. Selección de color base, rugosidad y metálico según zona
	vec3 color_zona = color_camiseta.rgb;
	float rugosidad_final = rugosidad_tela;
	float metalico_final = metalico_base;

	if (zona == 1) {
		color_zona = piel_ajustada;
		rugosidad_final = rugosidad_piel;
	} else if (zona == 2) {
		color_zona = pelo_ajustado;
		rugosidad_final = 0.68;
	} else if (zona == 3) {
		color_zona = color_camiseta.rgb;
		rugosidad_final = rugosidad_tela;
	} else if (zona == 4) {
		color_zona = color_secundario.rgb;
		rugosidad_final = 0.28;
		metalico_final = metalico_escudo;
	} else if (zona == 5) {
		color_zona = color_short.rgb;
		rugosidad_final = rugosidad_tela;
	} else if (zona == 6) {
		color_zona = color_medias.rgb;
		rugosidad_final = rugosidad_tela;
	} else if (zona == 7) {
		color_zona = color_botines.rgb;
		rugosidad_final = rugosidad_botin;
		metalico_final = 0.12;
	}

	// 4. Muestreo del Texture Atlas (Albedo + ORM + Normal Map)
	// Desplazamiento UV en Cuadrante 1 si se selecciona una variante facial del atlas
	vec2 uv_atlas = UV;
	if (id_zona_malla == 0 && UV.x < 0.5 && UV.y < 0.5) {
		float offset_x = float(variante_aspecto % 2) * 0.25;
		uv_atlas.x = clamp(UV.x * 0.5 + offset_x, 0.0, 0.499);
	}

	vec4 muestra_albedo = texture(textura_atlas_albedo, uv_atlas);
	vec3 muestra_orm = texture(textura_atlas_orm, uv_atlas).rgb;

	// Sombreado de pliegues por luminancia para prendas tintables (Camiseta, Shorts, Medias)
	// y preservación cromática directa para Rostro/Piel (zona 1) y Botines (zona 7).
	float luma_tela = dot(muestra_albedo.rgb, vec3(0.299, 0.587, 0.114));
	float sombreado_tela = clamp(luma_tela * 1.45, 0.42, 1.15);

	vec3 color_texturizado = color_zona * sombreado_tela;
	if (zona == 1) {
		// Rostro, ojos y piel del modelo 3D: conservar textura difusa original con variación de tono
		color_texturizado = muestra_albedo.rgb * (1.0 - factor_var * 0.55);
	} else if (zona == 2) {
		color_texturizado = mix(pelo_ajustado, muestra_albedo.rgb * pelo_ajustado * 1.6, 0.65);
	} else if (zona == 7) {
		color_texturizado = mix(color_zona * sombreado_tela, muestra_albedo.rgb, 0.55);
	}

	vec3 color_combinado = mix(color_zona, color_texturizado, mezcla_textura_atlas);

	// 5. Superposición de dorsal en Cuadrante 2 (espalda de camiseta en malla unificada)
	if (id_zona_malla == 0 && zona == 3) {
		float mascara_num = _calcular_mascara_dorsal(UV, dorsal_jugador);
		color_combinado = mix(color_combinado, color_dorsal.rgb, mascara_num);
	}

	ALBEDO = color_combinado;
	AO = mix(1.0, muestra_orm.r, mezcla_textura_atlas);
	ROUGHNESS = clamp(rugosidad_final * mix(1.0, muestra_orm.g, mezcla_textura_atlas), 0.05, 1.0);
	METALLIC = clamp(metalico_final * mix(1.0, muestra_orm.b, mezcla_textura_atlas), 0.0, 1.0);

	// 6. Proyección de pliegues de tela, costuras y relieve muscular mediante Normal Map
	NORMAL_MAP = texture(textura_atlas_normal, uv_atlas).rgb;
	NORMAL_MAP_DEPTH = intensidad_normal;
}
