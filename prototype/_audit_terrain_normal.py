"""Normal map audit - per memory note, a constant (0,0,0) normal = no
micro-detail, surface reads as smooth/glossy blob.
Normal maps in PBR are typically RGB = (X, Y, Z) where (0.5, 0.5, 1.0) =
flat. We want each channel to have variation; flat channels = broken
pipeline."""
from PIL import Image
import glob, os

print(f"{'file':42s} {'R range':>15s}  {'G range':>15s}  {'B range':>15s}  notes")
print("-" * 110)
flat_count = 0
for p in sorted(glob.glob(r"E:\Kitbash-Command\prototype\assets\textures\terrain\*_normal.png")):
    img = Image.open(p).convert('RGBA')
    r, g, b, a = img.split()
    rdata = list(r.getdata())
    gdata = list(g.getdata())
    bdata = list(b.getdata())
    rrange = max(rdata) - min(rdata)
    grange = max(gdata) - min(gdata)
    brange = max(bdata) - min(bdata)
    bmean = sum(bdata) / len(bdata)
    name = os.path.basename(p)
    notes = []
    if rrange < 5 and grange < 5 and brange < 5:
        notes.append("ALL-FLAT (zero micro-detail)")
        flat_count += 1
    elif rrange < 5:
        notes.append("R-FLAT")
    elif grange < 5:
        notes.append("G-FLAT")
    if bmean < 100:
        notes.append(f"B-BIASED-LOW(={bmean:.0f})")
    note_str = " | ".join(notes) if notes else "ok"
    print(f"{name:42s} {min(rdata):>3d}-{max(rdata):<3d}({rrange:>3d})  {min(gdata):>3d}-{max(gdata):<3d}({grange:>3d})  {min(bdata):>3d}-{max(bdata):<3d}(brange={brange:>3d},bmean={bmean:.0f})  {note_str}")

print(f"\n{flat_count} normal maps with zero micro-detail")
