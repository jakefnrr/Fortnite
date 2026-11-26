import numpy as np
import trimesh
from trimesh.transformations import rotation_matrix

BROWN = np.array([0.55, 0.30, 0.12, 1.0])
STEEL = np.array([0.65, 0.68, 0.72, 1.0])
DARK = np.array([0.25, 0.25, 0.28, 1.0])

parts = []


def paint(mesh, color):
    n = len(mesh.vertices)
    mesh.visual.vertex_colors = np.tile(color, (n, 1)).astype(np.uint8) if color.dtype != np.uint8 else np.tile(color, (n, 1))
    return mesh


def colorize(mesh, rgba):
    mesh.visual = trimesh.visual.ColorVisuals(mesh)
    colors = np.tile((rgba * 255).astype(np.uint8), (len(mesh.vertices), 1))
    mesh.visual.vertex_colors = colors
    return mesh


# Handle: chunky tapered box along +Y, grip at origin
handle = trimesh.creation.box(extents=[0.09, 0.9, 0.09])
handle.apply_translation([0, 0.45, 0])
parts.append(colorize(handle, BROWN))

# Pommel knob at bottom
pommel = trimesh.creation.cylinder(radius=0.07, height=0.08, sections=8)
pommel.apply_translation([0, 0.02, 0])
parts.append(colorize(pommel, DARK))

# Head crossbar along X at top of handle
bar = trimesh.creation.box(extents=[0.7, 0.07, 0.07])
bar.apply_translation([0, 0.9, 0])
parts.append(colorize(bar, STEEL))

# Pick blade on the right (+X): angled down like a real pick
blade = trimesh.creation.box(extents=[0.45, 0.05, 0.16])
blade.apply_transform(rotation_matrix(np.radians(-35), [0, 0, 1]))
blade.apply_translation([0.5, 0.82, 0])
parts.append(colorize(blade, STEEL))

# Adze on the left (-X): angled down the other way
adze = trimesh.creation.box(extents=[0.3, 0.05, 0.14])
adze.apply_transform(rotation_matrix(np.radians(35), [0, 0, 1]))
adze.apply_translation([-0.42, 0.84, 0])
parts.append(colorize(adze, DARK))

pickaxe = trimesh.util.concatenate(parts)
pickaxe.export("/Users/jake/Desktop/Godot/Fortnite/models/pickaxe.glb")
print("wrote pickaxe.glb:", len(pickaxe.vertices), "verts")
