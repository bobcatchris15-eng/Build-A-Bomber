import os
import sys
import subprocess
from pathlib import Path

# Append local path to import sizes
sys.path.append(r"E:\Build-A-Bomber")
try:
    from module_sizes import sizes
except ImportError:
    sizes = {}

IMAGE_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\temp_images")
RAW_MESH_DIR = Path(r"E:\Build-A-Bomber\TRIPO_GEN_Meshes")
FINAL_MODEL_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\models")

PYTHON_EXE = r"C:\Users\Chris\Documents\Modly\extensions\triposg\venv\Scripts\python.exe"
BLENDER_EXE = r"E:\Build-A-Bomber\prototype\UPBGE-0.30-windows-x86_64\blender.exe"

RUN_TRIPO_SCRIPT = r"E:\Build-A-Bomber\run_tripo.py"
CLEANUP_SCRIPT = r"E:\Build-A-Bomber\blender_cleanup.py"

def get_target_directory(base_name):
    # Determine which subfolder it goes to
    # Hulls
    if "hull" in base_name or "foundation" in base_name:
        return FINAL_MODEL_DIR / "hulls"
    
    # Buildings
    buildings = ["hq", "refinery", "manufactory", "power_plant"]
    if any(b in base_name for b in buildings):
        return FINAL_MODEL_DIR / "buildings"
        
    # Default is parts
    return FINAL_MODEL_DIR / "parts"

def process_image(img_path):
    base_name = img_path.stem
    print(f"\n==================================================")
    print(f"Processing: {base_name}")
    print(f"==================================================")
    
    # Target path
    target_dir = get_target_directory(base_name)
    target_dir.mkdir(parents=True, exist_ok=True)
    final_glb_path = target_dir / f"{base_name}.glb"
    
    # 1. Run TripoSG
    raw_glb_name = f"{base_name}.glb"
    raw_glb_path = RAW_MESH_DIR / raw_glb_name
    
    print(f"Step 1: Running TripoSG generation...")
    tripo_cmd = [
        PYTHON_EXE,
        RUN_TRIPO_SCRIPT,
        str(img_path),
        raw_glb_name
    ]
    
    try:
        subprocess.run(tripo_cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Error running TripoSG for {base_name}: {e}")
        return False
        
    # 2. Run Blender Cleanup
    print(f"Step 2: Running Blender cleanup & scaling...")
    blender_cmd = [
        BLENDER_EXE,
        "-b",
        "-P", CLEANUP_SCRIPT,
        "--",
        str(raw_glb_path),
        str(final_glb_path),
        base_name
    ]
    
    try:
        subprocess.run(blender_cmd, check=True)
        print(f"Successfully generated and cleaned: {final_glb_path}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"Error running Blender cleanup for {base_name}: {e}")
        return False

def main():
    IMAGE_DIR.mkdir(parents=True, exist_ok=True)
    images = list(IMAGE_DIR.glob("*.jpg")) + list(IMAGE_DIR.glob("*.png"))
    
    if not images:
        print(f"No source images found in {IMAGE_DIR}")
        print("Please place .jpg or .png images in that directory and run this script again.")
        return
        
    print(f"Found {len(images)} images to process.")
    success_count = 0
    
    for img_path in images:
        if process_image(img_path):
            success_count += 1
            # Move or delete processed image to avoid re-running?
            # For now we leave them, but we could move to a "processed" folder.
            processed_dir = IMAGE_DIR / "processed"
            processed_dir.mkdir(exist_ok=True)
            try:
                os.rename(img_path, processed_dir / img_path.name)
            except Exception as e:
                print(f"Could not move image: {e}")
            
    print(f"\nBatch processing finished! Successfully generated {success_count}/{len(images)} models.")

if __name__ == "__main__":
    main()
