"""PBR audit of the Kitbash Command terrain textures.
Per memory note 2026-08-18: roughness defaults to reading G, but the shader
at terrain_ground.gdshader:133 reads .r explicitly. Want to know which
textures have data in the right channel, and which are flat (= plastic).
"""
from PIL import Image
import glob, os

# A "flat" texture (single value across the whole surface) is the
# classic broken-pipeline placeholder - it tells the renderer "any value"
# which it then reads as 0 = full mirror. Flag any with range=0.
print(f"{'file':42s} {'R range':>10s}  {'G range':>10s}  notes")
print("-" * 100)

for p in sorted(glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\*_roughness.png")):
    img = Image.open(p).convert('RGBA')
    r, g, b, a = img.split()
    rdata = list(r.getdata())
    gdata = list(g.getdata())
    rmax, rmin = max(rdata), min(rdata)
    gmax, gmin = max(gdata), min(gdata)
    rmean = sum(rdata) / len(rdata)
    gmean = sum(gdata) / len(gdata)
    rrange = rmax - rmin
    grange = gmax - gmin
    name = os.path.basename(p)
    notes = []
    if rrange == 0:
        notes.append("R-FLAT")
    if grange == 0:
        notes.append("G-FLAT")
    if rmean > 250 and rrange > 100:
        notes.append("R-BIASED-HIGH")
    if rmean < 5 and rrange > 100:
        notes.append("R-BIASED-LOW")
    note_str = " | ".join(notes) if notes else "ok"
    print(f"{name:42s} {rmin:>3d}-{rmax:<3d}({rmean:5.1f}) {gmin:>3d}-{gmax:<3d}({gmean:5.1f})  {note_str}")
