import os
from PIL import Image, ImageDraw

# Derived from this file's own location, not hardcoded. The previous
# value was an absolute path into a checkout that no longer exists.
IMG_DIR = os.path.normpath(
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "temp_images")
)
os.makedirs(IMG_DIR, exist_ok=True)

def draw_hq(d):
    # Hexagonal Command Bunker
    d.polygon([(256, 120), (380, 180), (380, 320), (256, 380), (132, 320), (132, 180)], fill=(80, 90, 105), outline=(30, 40, 50), width=4)
    # Roof plate
    d.polygon([(256, 150), (340, 190), (340, 290), (256, 330), (172, 290), (172, 190)], fill=(120, 135, 155), outline=(40, 50, 65), width=3)
    # Central Command Dome
    d.ellipse([(216, 200), (296, 280)], fill=(50, 120, 200), outline=(20, 60, 120), width=4)
    # Radar mast
    d.line([(256, 240), (256, 140)], fill=(40, 50, 65), width=6)
    d.ellipse([(236, 130), (276, 150)], outline=(40, 50, 65), width=4)

def draw_refinery(d):
    # Processing Silos
    # Silo 1
    d.rectangle([(140, 160), (230, 380)], fill=(140, 150, 165), outline=(40, 50, 60), width=4)
    d.ellipse([(140, 130), (230, 190)], fill=(170, 180, 195), outline=(40, 50, 60), width=4)
    # Silo 2
    d.rectangle([(280, 160), (370, 380)], fill=(140, 150, 165), outline=(40, 50, 60), width=4)
    d.ellipse([(280, 130), (370, 190)], fill=(170, 180, 195), outline=(40, 50, 60), width=4)
    # Connecting pipe truss
    d.rectangle([(230, 220), (280, 260)], fill=(200, 120, 40), outline=(40, 50, 60), width=3)

def draw_light_manufactory(d):
    # Sawtooth Factory Building
    d.polygon([(120, 220), (210, 140), (210, 220), (300, 140), (300, 220), (390, 140), (390, 380), (120, 380)], fill=(160, 140, 110), outline=(40, 35, 25), width=4)
    # Garage bay door
    d.rectangle([(210, 280), (300, 380)], fill=(50, 60, 75), outline=(20, 25, 30), width=4)

def draw_medium_manufactory(d):
    # Assembly Plant with Vents
    d.polygon([(110, 180), (256, 120), (402, 180), (402, 380), (110, 380)], fill=(170, 130, 95), outline=(50, 35, 25), width=4)
    # Roof vent stacks
    d.rectangle([(170, 110), (200, 150)], fill=(80, 90, 100), outline=(30, 35, 40), width=3)
    d.rectangle([(312, 110), (342, 150)], fill=(80, 90, 100), outline=(30, 35, 40), width=3)
    # Blast doors
    d.rectangle([(200, 260), (312, 380)], fill=(40, 50, 60), outline=(15, 20, 25), width=4)

def draw_heavy_manufactory(d):
    # Heavy War Foundry
    d.rectangle([(100, 160), (412, 390)], fill=(130, 90, 80), outline=(40, 25, 20), width=5)
    # Heavy roof superstructure
    d.polygon([(140, 160), (256, 100), (372, 160)], fill=(170, 120, 100), outline=(40, 25, 20), width=4)
    # Main blast gate
    d.rectangle([(180, 240), (332, 390)], fill=(30, 35, 45), outline=(10, 15, 20), width=5)

def draw_power_plant(d):
    # Cooling Tower / Reactor Building
    d.polygon([(170, 130), (342, 130), (380, 380), (132, 380)], fill=(190, 180, 150), outline=(50, 45, 35), width=4)
    # Reactor glow rings
    d.ellipse([(200, 200), (312, 240)], fill=(240, 190, 40), outline=(180, 130, 20), width=3)
    d.ellipse([(210, 270), (302, 310)], fill=(240, 190, 40), outline=(180, 130, 20), width=3)

buildings = {
    "hq": draw_hq,
    "refinery": draw_refinery,
    "light_manufactory": draw_light_manufactory,
    "medium_manufactory": draw_medium_manufactory,
    "heavy_manufactory": draw_heavy_manufactory,
    "power_plant": draw_power_plant
}

for name, draw_fn in buildings.items():
    img = Image.new("RGB", (512, 512), (255, 255, 255))
    draw = ImageDraw.Draw(img)
    draw_fn(draw)
    path = os.path.join(IMG_DIR, f"{name}.png")
    img.save(path)
    print(f"Generated source image for building '{name}' at {path}")
