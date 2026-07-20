import os
import sys
import subprocess
from pathlib import Path

SOURCE_DIR = Path(r"E:\Testing Example Grounded Gen")
FINAL_MODEL_DIR = Path(r"E:\Build-A-Bomber\prototype\assets\models")
BLENDER_EXE = r"E:\Build-A-Bomber\prototype\UPBGE-0.30-windows-x86_64\blender.exe"
CLEANUP_SCRIPT = r"E:\Build-A-Bomber\blender_cleanup.py"

def process_file(file_path):
    base_name = file_path.stem
    
    # Determine target subdirectory based on parent folder name
    parent_name = file_path.parent.name.lower()
    if parent_name == "hulls":
        target_dir = FINAL_MODEL_DIR / "hulls"
    elif parent_name == "buildings":
        target_dir = FINAL_MODEL_DIR / "buildings"
    else:
        target_dir = FINAL_MODEL_DIR / "parts"
        
    target_dir.mkdir(parents=True, exist_ok=True)
    output_path = target_dir / f"{base_name}.glb"
    
    print(f"\nProcessing: {base_name}")
    print(f"  Source: {file_path}")
    print(f"  Output: {output_path}")
    
    blender_cmd = [
        BLENDER_EXE,
        "-b",
        "-P", CLEANUP_SCRIPT,
        "--",
        str(file_path),
        str(output_path),
        base_name
    ]
    
    try:
        subprocess.run(blender_cmd, check=True)
        print(f"  Successfully processed and copied: {base_name}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"  Error processing {base_name}: {e}")
        return False

def main():
    if not SOURCE_DIR.exists():
        print(f"Error: Source directory {SOURCE_DIR} does not exist.")
        sys.exit(1)
        
    glb_files = list(SOURCE_DIR.glob("**/*.glb"))
    if not glb_files:
        print(f"No .glb files found in {SOURCE_DIR}")
        sys.exit(1)
        
    print(f"Found {len(glb_files)} meshes to migrate and clean up.")
    
    success_count = 0
    for glb_file in glb_files:
        if process_file(glb_file):
            success_count += 1
            
    print(f"\nMigration Complete: {success_count}/{len(glb_files)} models successfully processed.")

if __name__ == "__main__":
    main()
