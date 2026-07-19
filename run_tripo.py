import os
import sys
import time
import uuid
from pathlib import Path
import io
from PIL import Image
import numpy as np

# Set up paths
MODLY_DIR = Path(r"C:\Users\Chris\Documents\Modly")
EXT_DIR = MODLY_DIR / "extensions" / "triposg"
VENDOR_DIR = EXT_DIR / "vendor"
MODEL_DIR = MODLY_DIR / "models" / "triposg" / "generate"
OUTPUT_DIR = Path(r"E:\Build-A-Bomber\TRIPO_GEN_Meshes")

OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Add to sys.path
sys.path.insert(0, str(VENDOR_DIR))

import torch
import trimesh
import rembg

try:
    from triposg.pipelines.pipeline_triposg import TripoSGPipeline
except ImportError as e:
    print(f"Failed to import TripoSGPipeline: {e}")
    sys.exit(1)

def preprocess_image(image_path, fg_ratio=0.85):
    image = Image.open(image_path).convert("RGBA")
    
    # Remove background
    try:
        session = rembg.new_session()
        image = rembg.remove(image, session=session)
    except Exception:
        session = rembg.new_session(providers=["CPUExecutionProvider"])
        image = rembg.remove(image, session=session)

    # Composite on white background
    bg = Image.new("RGBA", image.size, (255, 255, 255, 255))
    bg.paste(image, mask=image.split()[3])
    image = bg.convert("RGB")

    # Scale foreground
    arr = np.array(image)
    mask = ~np.all(arr >= 250, axis=-1)
    if not mask.any():
        return image

    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]

    fg = image.crop((cmin, rmin, cmax + 1, rmax + 1))
    fw, fh = fg.size
    iw, ih = image.size
    scale = fg_ratio * min(iw, ih) / max(fw, fh)
    nw = max(1, int(fw * scale))
    nh = max(1, int(fh * scale))
    fg = fg.resize((nw, nh), Image.LANCZOS)

    result = Image.new("RGB", (iw, ih), (255, 255, 255))
    result.paste(fg, ((iw - nw) // 2, (ih - nh) // 2))
    return result

def generate_mesh(image_path, output_filename=None):
    device = "cuda:0" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if torch.cuda.is_available() else torch.float32
    
    print(f"Loading TripoSG on {device}...")
    pipe = TripoSGPipeline.from_pretrained(str(MODEL_DIR)).to(device, dtype)
    
    print("Preprocessing image...")
    image = preprocess_image(image_path)
    
    print("Running TripoSG...")
    generator = torch.Generator(device=pipe.device).manual_seed(42)
    with torch.no_grad():
        outputs = pipe(
            image=image,
            generator=generator,
            num_inference_steps=50,
            guidance_scale=7.0,
            use_flash_decoder=False, # Use Marching Cubes
        ).samples[0]
        
    print("Extracting mesh...")
    mesh = trimesh.Trimesh(
        vertices=outputs[0].astype(np.float32),
        faces=np.ascontiguousarray(outputs[1]),
    )
    
    if output_filename is None:
        name = f"{Path(image_path).stem}.glb"
    else:
        name = output_filename
        
    path = OUTPUT_DIR / name
    print(f"Exporting to {path}...")
    mesh.export(str(path))
    
    del outputs
    del pipe
    del mesh
    import gc
    gc.collect()
    torch.cuda.empty_cache()
    
    return path

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python run_tripo.py <image_path> [output_filename]")
        sys.exit(1)
        
    img_path = sys.argv[1]
    out_name = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        generate_mesh(img_path, out_name)
        print("Done!")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
