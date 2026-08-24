"""Dump rocky variants at full size for direct comparison."""
from PIL import Image, ImageDraw
import os

OUT = r"E:\Kitbash-Command\prototype\assets\textures\terrain"
files = ["rocky_albedo.png", "rocky_v1_albedo.png", "rocky_v2_albedo.png", "rocky_v3_albedo.png",
         "rocky_v1_normal.png", "rocky_v2_normal.png", "rocky_v3_normal.png"]
W = 400
pad = 6
COLS = 4
ROWS = 2
canvas = Image.new("RGB", (COLS * (W + pad) + pad, ROWS * (W + 20 + pad) + pad), (32, 32, 32))
draw = ImageDraw.Draw(canvas)
for i, name in enumerate(files):
    r, c = i // COLS, i % COLS
    x = pad + c * (W + pad)
    y = pad + r * (W + 20 + pad)
    color = (220, 220, 220)
    if "_normal" in name: color = (130, 180, 255)
    draw.text((x, y), name, fill=color)
    p = os.path.join(OUT, name)
    if os.path.exists(p):
        img = Image.open(p).convert("RGB").resize((W, W))
        canvas.paste(img, (x, y + 16))
canvas.save(r"E:\Kitbash-Command\prototype\_rocky_dump.png")
print("wrote _rocky_dump.png")
