import os
import subprocess
from pathlib import Path
SOURCE_DIRS = [
    Path(r"E:\Testing Example Grounded Gen")
]
FINAL_MODEL_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\models")
BLENDER_EXE = r"E:\Build-A-Bomber\prototype\UPBGE-0.30-windows-x86_64\blender.exe"
CLEANUP_SCRIPT = r"E:\Build-A-Bomber\blender_cleanup.py"

def process_file(file_path):
    base_name = file_path.stem
    is_hull = "hull" in base_name or "foundation" in base_name
    folder = "hulls" if is_hull else "parts"
    target_dir = FINAL_MODEL_DIR / folder
    target_dir.mkdir(parents=True, exist_ok=True)
    output_path = target_dir / f"{base_name}.glb"
    
    print(f"\nProcessing: {base_name}")
    blender_cmd = [
        BLENDER_EXE,
        "-b",
        "-P", CLEANUP_SCRIPT,
        "--",
        str(file_path),
        str(output_path),
        base_name
    ]
    
    subprocess.run(blender_cmd, check=True)
    return True

def main():
    glb_files = []
    for d in SOURCE_DIRS:
        glb_files.extend(list(d.rglob("*.glb")))
        
    success_count = 0
    for glb in glb_files:
        if process_file(glb):
            success_count += 1
            
    print(f"\nProcessed {success_count} hull meshes.")

if __name__ == "__main__":
    main()
