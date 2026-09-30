"""Wrapper: run check_overflows.py with shell=True so flutter.bat resolves on Windows."""
import runpy
import subprocess

_orig_run = subprocess.run


def _patched_run(args, *a, **k):
    if isinstance(args, (list, tuple)) and args and args[0] == "flutter":
        k["shell"] = True
    return _orig_run(args, *a, **k)


subprocess.run = _patched_run
runpy.run_path(r"C:\Users\other8080\Videos\project\hk\check_overflows.py", run_name="__main__")
