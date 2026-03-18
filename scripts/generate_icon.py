#!/usr/bin/env python3
"""Generate FaceTracker app icon at all required macOS sizes."""

import math
from PIL import Image, ImageDraw

def draw_icon(size):
    """Draw a face-tracker icon: stylized eye with camera-lens pupil."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    s = size  # shorthand

    # Background: rounded rectangle with gradient-like dark blue
    pad = int(s * 0.08)
    radius = int(s * 0.18)
    # Dark background
    draw.rounded_rectangle(
        [pad, pad, s - pad, s - pad],
        radius=radius,
        fill=(20, 25, 45, 255)
    )

    # Subtle inner glow
    inner_pad = pad + int(s * 0.02)
    draw.rounded_rectangle(
        [inner_pad, inner_pad, s - inner_pad, s - inner_pad],
        radius=radius - int(s * 0.02),
        fill=(25, 32, 55, 255)
    )

    cx, cy = s // 2, s // 2

    # Draw eye shape (almond) using an ellipse approach
    eye_w = int(s * 0.60)
    eye_h = int(s * 0.30)

    # Eye white (slightly blue-tinted)
    draw.ellipse(
        [cx - eye_w // 2, cy - eye_h // 2, cx + eye_w // 2, cy + eye_h // 2],
        fill=(200, 220, 240, 255),
        outline=(100, 140, 180, 255),
        width=max(1, int(s * 0.008))
    )

    # Iris (teal/green)
    iris_r = int(s * 0.12)
    draw.ellipse(
        [cx - iris_r, cy - iris_r, cx + iris_r, cy + iris_r],
        fill=(40, 180, 140, 255),
        outline=(30, 140, 110, 255),
        width=max(1, int(s * 0.006))
    )

    # Camera lens rings inside the iris
    for ring_ratio in [0.75, 0.5]:
        r = int(iris_r * ring_ratio)
        draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            outline=(20, 100, 80, 180),
            width=max(1, int(s * 0.004))
        )

    # Pupil (dark center)
    pupil_r = int(iris_r * 0.30)
    draw.ellipse(
        [cx - pupil_r, cy - pupil_r, cx + pupil_r, cy + pupil_r],
        fill=(10, 15, 30, 255)
    )

    # Specular highlight on iris
    hl_x = cx - int(iris_r * 0.3)
    hl_y = cy - int(iris_r * 0.3)
    hl_r = int(iris_r * 0.15)
    draw.ellipse(
        [hl_x - hl_r, hl_y - hl_r, hl_x + hl_r, hl_y + hl_r],
        fill=(255, 255, 255, 200)
    )

    # Camera aperture blades (subtle, inside iris)
    blade_r = int(iris_r * 0.85)
    num_blades = 6
    for i in range(num_blades):
        angle = (2 * math.pi * i / num_blades) - math.pi / 2
        next_angle = (2 * math.pi * (i + 1) / num_blades) - math.pi / 2
        x1 = cx + int(blade_r * math.cos(angle))
        y1 = cy + int(blade_r * math.sin(angle))
        x2 = cx + int(blade_r * math.cos(next_angle))
        y2 = cy + int(blade_r * math.sin(next_angle))
        draw.line([(x1, y1), (x2, y2)], fill=(20, 100, 80, 100), width=max(1, int(s * 0.003)))

    # Green/red indicators at bottom corners
    ind_r = int(s * 0.04)
    ind_y = s - pad - int(s * 0.08)

    # Green dot (left)
    gx = pad + int(s * 0.12)
    draw.ellipse([gx - ind_r, ind_y - ind_r, gx + ind_r, ind_y + ind_r],
                 fill=(74, 222, 128, 255))

    # Red dot (right)
    rx = s - pad - int(s * 0.12)
    draw.ellipse([rx - ind_r, ind_y - ind_r, rx + ind_r, ind_y + ind_r],
                 fill=(239, 68, 68, 255))

    return img


# Generate all required macOS icon sizes
sizes = {
    'icon_16x16.png': 16,
    'icon_16x16@2x.png': 32,
    'icon_32x32.png': 32,
    'icon_32x32@2x.png': 64,
    'icon_128x128.png': 128,
    'icon_128x128@2x.png': 256,
    'icon_256x256.png': 256,
    'icon_256x256@2x.png': 512,
    'icon_512x512.png': 512,
    'icon_512x512@2x.png': 1024,
}

output_dir = 'Sources/Assets.xcassets/AppIcon.appiconset'

# Generate the master at 1024 and resize down for quality
master = draw_icon(1024)

for filename, size in sizes.items():
    resized = master.resize((size, size), Image.LANCZOS)
    resized.save(f'{output_dir}/{filename}', 'PNG')
    print(f'  Generated {filename} ({size}x{size})')

print('Done!')
