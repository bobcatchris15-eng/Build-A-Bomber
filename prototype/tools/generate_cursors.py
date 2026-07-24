import os
from PIL import Image, ImageDraw

CURSOR_DIR = r"e:\Build-A-Bomber-GitHub\prototype\assets\cursors"
os.makedirs(CURSOR_DIR, exist_ok=True)

def create_cursor(name, draw_fn):
    img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw_fn(draw)
    img.save(os.path.join(CURSOR_DIR, f"{name}.png"))

def draw_default(d):
    # Arrow cursor with cyan trim
    d.polygon([(0, 0), (0, 24), (6, 18), (12, 28), (16, 26), (10, 16), (18, 16)], fill=(20, 25, 30, 240), outline=(56, 189, 248, 255))

def draw_pointer(d):
    # Hand pointer
    d.polygon([(8, 2), (12, 2), (12, 14), (16, 14), (20, 18), (18, 26), (8, 26)], fill=(20, 25, 30, 240), outline=(250, 204, 21, 255))

def draw_move(d):
    # 4-way arrow crosshair
    d.line([(16, 4), (16, 28)], fill=(56, 189, 248, 255), width=2)
    d.line([(4, 16), (28, 16)], fill=(56, 189, 248, 255), width=2)
    d.ellipse([(12, 12), (20, 20)], outline=(56, 189, 248, 255), width=2)

def draw_attack(d):
    # Red targeting reticle
    d.ellipse([(6, 6), (26, 26)], outline=(239, 68, 68, 255), width=2)
    d.line([(16, 2), (16, 30)], fill=(239, 68, 68, 255), width=2)
    d.line([(2, 16), (30, 16)], fill=(239, 68, 68, 255), width=2)

def draw_harvest(d):
    # Orange pickaxe / gear icon
    d.line([(6, 26), (22, 10)], fill=(249, 115, 22, 255), width=4)
    d.line([(14, 6), (26, 18)], fill=(251, 146, 60, 255), width=3)

def draw_invalid(d):
    # Forbidden red circle with slash
    d.ellipse([(4, 4), (28, 28)], outline=(239, 68, 68, 255), width=3)
    d.line([(8, 8), (24, 24)], fill=(239, 68, 68, 255), width=3)

def draw_build(d):
    # Green hammer / grid
    d.rectangle([(8, 8), (24, 24)], outline=(74, 222, 128, 255), width=2)
    d.line([(16, 8), (16, 24)], fill=(74, 222, 128, 255), width=2)
    d.line([(8, 16), (24, 16)], fill=(74, 222, 128, 255), width=2)

create_cursor("cursor_default", draw_default)
create_cursor("cursor_pointer", draw_pointer)
create_cursor("cursor_move", draw_move)
create_cursor("cursor_attack", draw_attack)
create_cursor("cursor_harvest", draw_harvest)
create_cursor("cursor_invalid", draw_invalid)
create_cursor("cursor_build", draw_build)

print("Generated 7 PNG cursor assets in assets/cursors/")
