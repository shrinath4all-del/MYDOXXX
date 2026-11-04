@echo off
setlocal
where py >nul 2>nul
if not errorlevel 1 (
  py -3 "%~dp0start.py" %*
  goto finished
)
where python >nul 2>nul
if not errorlevel 1 (
  python "%~dp0start.py" %*
  goto finished
)
where python3 >nul 2>nul
if not errorlevel 1 (
  python3 "%~dp0start.py" %*
  goto finished
)
echo Python 3.10 or newer is needed on this laptop. Nothing was installed.
echo Read START-HERE.md or ask Codex to find an available local Python runtime.
pause
exit /b 2
:finished
if errorlevel 1 (
  echo.
  echo The test room could not start. Read the message above and START-HERE.md.
  pause
)
endlocal
