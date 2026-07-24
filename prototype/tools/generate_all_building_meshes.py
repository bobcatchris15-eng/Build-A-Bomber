import os
import subprocess
import sys

PYTHON_EXE = r"C:\Users\Chris\Documents\Modly\extensions\triposg\venv\Scripts\python.exe"
RUN_TRIPO = r"e:\Build-A-Bomber-GitHub\run_tripo.py"
IMG_DIR = r"e:\Build-A-Bomber-GitHub\prototype\assets\temp_images"
OUT_DIR = r"e:\Build-A-Bomber-GitHub\prototype\assets\models\buildings"

os.makedirs(OUT_DIR, exist_ok=True)

buildings = ["hq", "refinery", "light_manufactory", "medium_manufactory", "heavy_manufactory", "power_plant"]

print(f"Starting TripoSG GLB generation for {len(buildings)} building types...")

for name in buildings:
    img_path = os.path.join(IMG_DIR, f"{name}.png")
    out_name = f"{name}.glb"
    out_path = os.path.join(OUT_DIR, out_name)
    
    if os.path.exists(out_path):
        print(f"[{name}] GLB mesh already exists at {out_path}, skipping.")
        continue
        
    print(f"[{name}] Generating 3D GLB mesh via TripoSG...")
    cmd = [PYTHON_EXE, RUN_TRIPO, img_path, out_name]
    try:
        ret = subprocess.run(cmd, check=True, text=True, capture_output=True)
        print(f"[{name}] Success! Exported to {out_path}")
    except subprocess.CalledProcessError as e:
        print(f"[{name}] Error generating mesh: {e.stderr}")

print("TripoSG building mesh generation pass complete!")
