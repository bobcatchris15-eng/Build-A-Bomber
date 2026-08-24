"""Save the test range's ground textures to a side-by-side image for inspection."""
from PIL import Image
import os

OUT = r"E:\Kitbash-Command\prototype\assets\textures\terrain"
files = [
    "grassland_albedo.png",
    "grassland_normal.png",
    "grassland_roughness.png",
    "grassland_v1_albedo.png",
    "grassland_v2_albedo.png",
    "grassland_v3_albedo.png",
    "grassland_v1_normal.png",
    "grassland_v2_normal.png",
    "grassland_v3_normal.png",
    "cobble_albedo.png",
    "cobble_normal.png",
]
imgs = []
for f in files:
    p = os.path.join(OUT, f)
    if not os.path.exists(p):
        print(f"missing: {f}")
        continue
    imgs.append((f, Image.open(p).convert("RGB")))

W, H = 256, 256
pad = 8
COLS = 3
ROWS = (len(imgs) + COLS - 1) // COLS
canvas = Image.new("RGB", (COLS * (W + pad) + pad, ROWS * (H + 20 + pad) + pad), (32, 32, 32))
from PIL import ImageDraw, ImageFont
draw = ImageDraw.Draw(canvas)
for i, (name, img) in enumerate(imgs):
    r, c = i // COLS, i % COLS
    x = pad + c * (W + pad)
    y = pad + r * (H + 20 + pad)
    draw.text((x, y), name[:24], fill=(220, 220, 220))
    canvas.paste(img.resize((W, H)), (x, y + 16))
canvas.save(r"E:\Kitbash-Command\prototype\_ground_dump.png")
print("wrote _ground_dump.png")
