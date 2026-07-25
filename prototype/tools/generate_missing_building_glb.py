import os
import sys
import gc
import torch

# Force garbage collection and CUDA cache empty
gc.collect()
if torch.cuda.is_available():
    torch.cuda.empty_cache()

from pathlib import Path
MODLY_DIR = Path(r"C:\Users\Chris\Documents\Modly")
EXT_DIR = MODLY_DIR / "extensions" / "triposg"
VENDOR_DIR = EXT_DIR / "vendor"
MODEL_DIR = MODLY_DIR / "models" / "triposg" / "generate"
OUT_DIR = Path(r"e:\Build-A-Bomber-GitHub\prototype\assets\models\buildings")
IMG_DIR = Path(r"e:\Build-A-Bomber-GitHub\prototype\assets\temp_images")

sys.path.insert(0, str(VENDOR_DIR))
from triposg.pipelines.pipeline_triposg import TripoSGPipeline
from PIL import Image
import rembg
import numpy as np
import trimesh

def process(name):
    out_file = OUT_DIR / f"{name}.glb"
    if out_file.exists():
        print(f"[{name}] Already exists at {out_file}")
        return
        
    img_path = IMG_DIR / f"{name}.png"
    print(f"[{name}] Preprocessing {img_path}...")
    image = Image.open(img_path).convert("RGBA")
    try:
        session = rembg.new_session()
        image = rembg.remove(image, session=session)
    except Exception:
        session = rembg.new_session(providers=["CPUExecutionProvider"])
        image = rembg.remove(image, session=session)

    bg = Image.new("RGBA", image.size, (255, 255, 255, 255))
    bg.paste(image, mask=image.split()[3])
    image = bg.convert("RGB")

    print(f"[{name}] Loading pipeline...")
    device = "cuda:0" if torch.cuda.is_available() else "cpu"
    dtype = torch.float16 if torch.cuda.is_available() else torch.float32
    pipe = TripoSGPipeline.from_pretrained(str(MODEL_DIR)).to(device, dtype)

    print(f"[{name}] Generating TripoSG mesh...")
    generator = torch.Generator(device=pipe.device).manual_seed(42)
    with torch.no_grad():
        outputs = pipe(
            image=image,
            generator=generator,
            num_inference_steps=25,
            guidance_scale=7.0,
            use_flash_decoder=False,
        ).samples[0]

    mesh = trimesh.Trimesh(
        vertices=outputs[0].astype(np.float32),
        faces=np.ascontiguousarray(outputs[1]),
    )
    print(f"[{name}] Exporting GLB to {out_file}...")
    mesh.export(str(out_file))
    print(f"[{name}] Done!")

for bname in ["medium_manufactory", "power_plant"]:
    try:
        process(bname)
    except Exception as e:
        print(f"Failed {bname}: {e}")
