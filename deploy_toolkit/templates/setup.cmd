@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Change to repo root (where this script lives)
cd /d "%~dp0"

REM Locate Git Bash
set "BASH_EXE=bash"
where bash >NUL 2>&1
if errorlevel 1 (
  if exist "%ProgramFiles%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\bin\bash.exe"
  ) else if exist "%ProgramFiles%\Git\usr\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles%\Git\usr\bin\bash.exe"
  ) else if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" (
    set "BASH_EXE=%ProgramFiles(x86)%\Git\bin\bash.exe"
  ) else (
    echo [ERR ] Git Bash not found. Install Git for Windows and retry.
    echo        https://git-scm.com/download/win
    exit /b 1
  )
)

echo [INFO] Launching bootstrap via Git Bash...
"%BASH_EXE%" deploy_toolkit/scripts/bootstrap.sh --env conda --name analyst-toolkit --copy-notebook --generate-configs --run-smoke %*
set EXITCODE=%ERRORLEVEL%
if not "%EXITCODE%"=="0" (
  echo [ERR ] Bootstrap failed with exit code %EXITCODE%.
  exit /b %EXITCODE%
)
echo [INFO] Done.

