@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel%==0 (
  py -3 "%~dp0discover.py" wizard
) else (
  where python >nul 2>nul
  if %errorlevel%==0 (
    python "%~dp0discover.py" wizard
  ) else (
    echo Python 3.9 o superior no esta instalado.
    echo Consulta setup.ps1 para diagnostico e instalacion opcional.
  )
)
echo.
pause
