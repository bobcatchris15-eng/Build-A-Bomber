"""Quick spot-check of the variant ranges after dialing back VARIANT_PARAMS."""
from PIL import Image
import glob, os
for p in sorted(glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\cobble*_roughness.png") +
                glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\dry_grass*_roughness.png") +
                glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\grassland*_roughness.png") +
                glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\dirt*_roughness.png")):
    img = Image.open(p).convert('RGBA')
    r = list(img.split()[0].getdata())
    print(f'{os.path.basename(p):42s} R {min(r):>3d}-{max(r):<3d} (mean={sum(r)/len(r):.0f}, range={max(r)-min(r)})')
