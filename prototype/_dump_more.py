"""Dump the test-range-relevant textures: rocky, cobble, all variants."""
from PIL import Image, ImageDraw
import os, glob

OUT = r"E:\Kitbash-Command\prototype\assets\textures\terrain"
files = []
# rocky: the zone directly in front of the player spawn (-15, 0, -30)
for base in ["rocky", "cobble", "grassland", "marsh", "gravel", "ice"]:
    for suffix in ["", "_v1", "_v2", "_v3"]:
        kind = "albedo"
        p = os.path.join(OUT, f"{base}{suffix}_{kind}.png")
        if os.path.exists(p):
            files.append(p)
        kind = "normal"
        p = os.path.join(OUT, f"{base}{suffix}_{kind}.png")
        if os.path.exists(p):
            files.append(p)
        kind = "roughness"
        p = os.path.join(OUT, f"{base}{suffix}_{kind}.png")
        if os.path.exists(p):
            files.append(p)
# Detail normal
p = os.path.join(OUT, "detail_normal.png")
if os.path.exists(p):
    files.append(p)

W, H = 200, 200
pad = 4
COLS = 6
ROWS = (len(files) + COLS - 1) // COLS
canvas = Image.new("RGB", (COLS * (W + pad) + pad, ROWS * (18 + pad) + pad), (24, 24, 24))
draw = ImageDraw.Draw(canvas)
for i, path in enumerate(files):
    r, c = i // COLS, i % COLS
    x = pad + c * (W + pad)
    y = pad + r * (18 + H + pad)
    name = os.path.basename(path)
    # Colour-code: albedos white, normals blue, roughness green
    color = (220, 220, 220)
    if "_normal" in name: color = (130, 180, 255)
    if "_roughness" in name: color = (180, 255, 180)
    draw.text((x, y), name[:30], fill=color)
    img = Image.open(path).convert("RGB")
    canvas.paste(img.resize((W, H)), (x, y + 14))
canvas.save(r"E:\Kitbash-Command\prototype\_ground_dump2.png")
print(f"wrote {len(files)} textures to _ground_dump2.png")
