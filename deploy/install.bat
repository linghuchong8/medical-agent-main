@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0.."

echo ============================================
echo  Tiangong Medical Agent - Deploy first time
echo ============================================

REM ---------- 0. Locate Python ----------
set "PYTHON=python"
python --version >nul 2>&1
if not errorlevel 1 goto python_ok
py -3.13 --version >nul 2>&1
if errorlevel 1 goto no_python
set "PYTHON=py -3.13"
:python_ok

REM ---------- 1. venv + dependencies ----------
echo.
echo [1/7] Checking virtual env...
if not exist ".venv\Scripts\python.exe" (
    echo   Creating venv...
    %PYTHON% -m venv .venv
    if errorlevel 1 goto venv_fail
    echo   Installing dependencies, a few minutes...
    ".venv\Scripts\python.exe" -m pip install --upgrade pip
    ".venv\Scripts\python.exe" -m pip install -r requirements.txt
    if errorlevel 1 goto pip_fail
) else (
    echo   venv already exists
)

REM ---------- 2. .env ----------
echo.
echo [2/7] Checking .env config...
if not exist ".env" (
    copy .env.example .env >nul
    echo   .env created. Please open it and set DEEPSEEK_API_KEY:
    echo     e.g.  DEEPSEEK_API_KEY=sk-xxxxxxxx
    echo.
    notepad .env
    echo   After saving, press any key to continue...
    pause >nul
) else (
    echo   .env already exists
)

REM ---------- 3. Docker ----------
set "DOCKER=docker"
if exist "%ProgramFiles%\Docker\Docker\resources\bin\docker.exe" set "DOCKER=%ProgramFiles%\Docker\Docker\resources\bin\docker.exe"

echo.
echo [3/7] Checking Docker...
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

REM ---------- 4. Start infra containers ----------
echo.
echo [4/7] Starting infra containers...
"%DOCKER%" compose up -d
if errorlevel 1 goto compose_fail
echo   Waiting for containers, max 5 min...
set /a tries=0
:wait_healthy
set /a tries+=1
if %tries% geq 60 goto healthy_timeout
ping -n 6 127.0.0.1 >nul
set HEALTHY=0
"%DOCKER%" compose ps --format "{{.Status}}" > "%TEMP%\tg_ps.txt" 2>nul
findstr /i "starting unhealthy" "%TEMP%\tg_ps.txt" >nul && set HEALTHY=1
if "!HEALTHY!"=="1" goto wait_healthy
echo   Containers ready.

REM ---------- 5. Init DB, first time ----------
echo.
echo [5/7] Initializing database...
if not exist ".deployed" goto do_init
echo   Already initialized, skip.
goto init_done
:do_init
echo   Creating tables with alembic...
".venv\Scripts\python.exe" -m alembic upgrade head
if errorlevel 1 goto alembic_fail
echo   Importing PostgreSQL data, 2-3 min...
".venv\Scripts\python.exe" scripts/init_postgres.py
if errorlevel 1 goto pg_fail
echo   Building Neo4j knowledge graph, 5-10 min...
".venv\Scripts\python.exe" scripts/init_neo4j.py
if errorlevel 1 goto neo4j_fail
echo. > .deployed
echo   Database initialized.
:init_done

REM ---------- 6. Ollama ----------
set "OLLAMA=ollama"
if exist "%LOCALAPPDATA%\Programs\Ollama\ollama.exe" set "OLLAMA=%LOCALAPPDATA%\Programs\Ollama\ollama.exe"

echo.
echo [6/7] Checking Ollama...
powershell -NoProfile -Command "try { (Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/version' -UseBasicParsing -TimeoutSec 5).Content | Out-Null; exit 0 } catch { exit 1 }" >nul 2>&1
if errorlevel 1 (
    echo   [WARN] Ollama not running. Long-term memory unavailable, chat still works.
    echo   Please start Ollama and re-run this script.
) else (
    echo   Ollama running
    "%OLLAMA%" list 2>nul | findstr /i "nomic-embed-text" >nul
    if errorlevel 1 (
        echo   Pulling embedding model nomic-embed-text, about 274MB...
        "%OLLAMA%" pull nomic-embed-text
    ) else (
        echo   embedding model ready
    )
)

REM ---------- 7. Done ----------
echo.
echo [7/7] Deployment finished!
echo   Daily start: deploy\start.bat  or double-click start_dev.bat
pause
exit /b 0

:no_python
echo   [ERROR] Python not found. Please install Python 3.13 and check "Add Python to PATH".
echo   See deploy/DEPLOYMENT.md section 3.1
pause
exit /b 1

:venv_fail
echo   [ERROR] Failed to create virtual env.
pause
exit /b 1

:pip_fail
echo   [ERROR] Failed to install dependencies. Check your network and retry.
pause
exit /b 1

:docker_timeout
echo   [ERROR] Docker start timed out. Please open Docker Desktop manually.
pause
exit /b 1

:compose_fail
echo   [ERROR] Failed to start infra containers. Run: docker compose ps
pause
exit /b 1

:healthy_timeout
echo   [ERROR] Containers not ready after 5 min. Run: docker compose ps
pause
exit /b 1

:alembic_fail
echo   [ERROR] Database migration failed.
pause
exit /b 1

:pg_fail
echo   [ERROR] PostgreSQL data import failed.
pause
exit /b 1

:neo4j_fail
echo   [ERROR] Neo4j knowledge graph build failed.
pause
exit /b 1
