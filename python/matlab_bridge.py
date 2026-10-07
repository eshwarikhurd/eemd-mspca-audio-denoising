"""Run the MATLAB denoising methods on a benchmark work folder via `matlab -batch`."""

import glob
import os
import shutil
import subprocess
from pathlib import Path

MATLAB_DIR = Path(__file__).resolve().parent.parent / "matlab"


def find_matlab(explicit=None):
    """MATLAB executable: explicit path, $MATLAB_BIN, `matlab` on PATH, or newest /Applications install."""
    for candidate in (explicit, os.environ.get("MATLAB_BIN"), shutil.which("matlab")):
        if candidate:
            return candidate
    apps = sorted(glob.glob("/Applications/MATLAB_R*.app/bin/matlab"))
    if apps:
        return apps[-1]
    raise FileNotFoundError("MATLAB not found. Pass --matlab or set MATLAB_BIN.")


def run_command(command, matlab=None):
    """Run a MATLAB command with matlab/ on the path."""
    subprocess.run([find_matlab(matlab), "-batch", f"addpath('{MATLAB_DIR}'); {command}"], check=True)


def run_batch(work_dir, matlab=None):
    """Process every jobs_<method>.txt in work_dir with matlab/denoise_batch.m."""
    run_command(f"denoise_batch('{Path(work_dir).resolve()}')", matlab)
