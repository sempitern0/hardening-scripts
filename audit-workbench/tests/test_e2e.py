"""Compatibility entrypoint for current Audit Workbench browser regression."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('test_v5.py')),run_name='__main__')
