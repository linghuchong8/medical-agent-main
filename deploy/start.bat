@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0.."

echo ============================================
echo  Tiangong Medical Agent - Start daily
echo ============================================

REM ---------- 0. Auto-deploy if not deployed ----------
if not exist ".deployed" (
    echo   Not deployed yet, auto-running deploy...
    call "%~dp0install.bat"
    if errorlevel 1 exit /b 1
)

set "DOCKER=docker"
if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" set "DOCKER=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"

REM ---------- 1. Docker ----------
echo.
echo [1/3] Checking Docker...
"%DOCKER%" version >nul 2>&1
if errorlevel 1 goto start_docker
goto docker_ready
:start_docker
echo   Starting Docker Desktop...
start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
echo   Waiting for Docker, max 5 min...
set /a tries=0
:wait_docker
set /a tries+=1
if %tries% geq 60 goto docker_timeout
ping -n 6 127.0.0.1 >nul
"%DOCKER%" version >nul 2>&1
if errorlevel 1 goto wait_docker
:docker_ready
echo   Docker ready.

REM ---------- 2. Containers ----------
echo.
echo [2/3] Ensuring containers are running...
"%DOCKER%" compose up -d
if errorlevel 1 goto compose_fail
echo   Containers started.

REM ---------- 3. App ----------
echo.
echo [3/3] Starting app at http://localhost:8080 ...
echo   Press Ctrl+C to stop
echo.
REM Clear stale env vars so the key in .env takes effect
set DEEPSEEK_API_KEY=
set DASHSCOPE_API_KEY=
set HTTP_PROXY=
set HTTPS_PROXY=
set ALL_PROXY=
".venv\Scripts\python.exe" -m uvicorn src.main:app --host 0.0.0.0 --port 8080
pause
exit /b 0

:docker_timeout
echo   [ERROR] Docker start timed out. Please open Docker Desktop manually.
pause
exit /b 1

:compose_fail
echo   [ERROR] Failed to start containers. Run: docker compose ps
pause
exit /b 1
