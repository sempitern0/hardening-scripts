"""Historical alias; v5 includes the previous form/PDF regression coverage."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('test_v5.py')),run_name='__main__')
