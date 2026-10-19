---
name: godot4-futsal
description: Especialista en arquitectura de escenas Godot 4 (Compatibility / GLES3) para juegos de futsal 3D Low-Poly en móviles Android.
---

# Reglas y Estándares de Desarrollo 3D

1. **Arquitectura y Escenas (.tscn):**
   - Prohibido generar la estructura principal por código mediante add_child().
   - Construye jerarquías visuales limpias en archivos `.tscn` 3D (Node3D, StaticBody3D, CharacterBody3D, RigidBody3D).
   - Para el prototipo 3D Low-Poly inicial, utiliza nodos CSG (CSGBox3D, CSGCylinder3D, CSGSphere3D) o MeshInstance3D con mallas primitivas (BoxMesh, CapsuleMesh) y StandardMaterial3D de colores planos.

2. **Convenciones de GDScript 2.0:**
   - Tipado estático estricto en todas las variables, parámetros y retornos (`var velocidad: float = 8.0`).
   - Uso de `@export` para física (gravedad, fricción, rebote, fuerza de tiro) y `@onready` para nodos hijos.
   - Renderizador: Compatibility (OpenGL ES 3.0 / GLES3).

3. **Mecánica Futsal 3D:**
   - Cancha 3D de 40x20 unidades con suelo, líneas y porterías.
   - Balón con RigidBody3D, colisión esférica y física pesada (bajo rebote).
   - Cámara en perspectiva cenital / isométrica dinámica (Camera3D) siguiendo la acción.