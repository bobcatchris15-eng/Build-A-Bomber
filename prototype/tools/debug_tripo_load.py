import sys
import traceback
from pathlib import Path

VENDOR_DIR = Path(r"C:\Users\Chris\Documents\Modly\extensions\triposg\vendor")
MODEL_DIR = Path(r"C:\Users\Chris\Documents\Modly\models\triposg\generate").resolve().as_posix()

sys.path.insert(0, str(VENDOR_DIR))

print(f"Loading TripoSGPipeline from posix path: {MODEL_DIR}")
import torch
from triposg.pipelines.pipeline_triposg import TripoSGPipeline

try:
    pipe = TripoSGPipeline.from_pretrained(MODEL_DIR)
    print("SUCCESS: TripoSGPipeline loaded clean on CPU!")
    if torch.cuda.is_available():
        print("Moving to CUDA GPU...")
        pipe = pipe.to("cuda", torch.float16)
        print("SUCCESS: TripoSGPipeline moved to CUDA GPU clean!")
except Exception as e:
    print("ERROR:")
    traceback.print_exc()
