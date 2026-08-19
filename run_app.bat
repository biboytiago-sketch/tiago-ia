@echo off
REM ============================================================
REM Script de inicializacao Tiago IA - Backend + Frontend Flutter Web
REM Atualizado: Resiliente a falta de Python no PATH
REM ============================================================
setlocal enableextensions enabledelayedexpansion
set "ROOT=%~dp0"
set "BACKEND_DIR=%ROOT%backend"
set "FRONTEND_DIR=%ROOT%frontend_flutter"
set "PY_CMD="

echo ========================================
echo   TIAGO IA - INICIALIZADOR
echo ========================================
echo.

REM --- DETECTAR PYTHON ---
echo [1/4] Detectando Python...
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
    set "PY_CMD=py -3"
    echo.    - Encontrado: py launcher (Python ^>= 3)
) else (
    where python >nul 2>nul
    if %ERRORLEVEL% EQU 0 (
        echo.    - Testando python.exe real (nao stub da Store)...
        python --version >nul 2>nul
        if !ERRORLEVEL! EQU 0 (
            set "PY_CMD=python"
            for /f "tokens=*" %%i in ('python --version 2^>^&1') do echo.    - Encontrado: %%i
        ) else (
            echo.    - AVISO: python.exe detectado e um STUB da Microsoft Store.
            goto :PYTHON_NAO_INSTALADO
        )
    ) else (
        goto :PYTHON_NAO_INSTALADO
    )
)
echo.

REM --- INSTALAR DEPENDENCIAS BACKEND ---
echo [2/4] Instalando dependencias do backend...
cd /d "%BACKEND_DIR%"
%PY_CMD% -m pip install --upgrade pip >nul
%PY_CMD% -m pip install -r requirements.txt
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo ERRO: Falha ao instalar dependencias Python.
    echo Verifique sua conexao e tente novamente.
    pause
    exit /b 1
)
echo.    - Dependencias instaladas com sucesso.
echo.

REM --- INICIAR UVICORN ---
echo [3/4] Iniciando servidor FastAPI (Uvicorn) na porta 8000...
start "Tiago IA - Backend" /D "%BACKEND_DIR%" cmd /k "%PY_CMD% -m uvicorn main:app --host 0.0.0.0 --port 8000 --reload"
echo.    - Aguardando 5 segundos para subir o servidor...
timeout /t 5 /nobreak >nul
echo.

REM --- INICIAR FLUTTER WEB ---
echo [4/4] Inicializando Flutter Web na porta 8080...
where flutter >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo.    - AVISO: Flutter nao encontrado no PATH.
    echo.      Verifique: https://docs.flutter.dev/get-started/install
    echo.
    echo Backend subiu. Tente iniciar o Flutter manualmente:
    echo   cd "%FRONTEND_DIR%" ^&^& flutter pub get ^&^& flutter run -d chrome --web-port 8080
    pause
    exit /b 0
)
cd /d "%FRONTEND_DIR%"
call flutter pub get
start "Tiago IA - Frontend Flutter" /D "%FRONTEND_DIR%" cmd /k "flutter run -d chrome --web-port 8080"

echo.
echo ========================================
echo   SISTEMA INICIADO!
echo   Backend API:  http://localhost:8000
echo   Frontend Web: http://localhost:8080
echo ========================================
echo.
pause
exit /b 0

:PYTHON_NAO_INSTALADO
echo.
echo ================================================================
echo  ERRO CRITICO: Python NAO esta instalado corretamente!
echo ================================================================
echo.
echo  O que fazer:
echo   1. Baixe o Python 3.11+ (64-bit) de:
echo      https://www.python.org/downloads/
echo.
echo   2. NA INSTALACAO, MARQUE A OPCAO:
echo      "[x] Add Python.exe to PATH"
echo.
echo   3. Instale o Python, FECHE e REABRA este terminal/PowerShell
echo      para que o PATH seja atualizado.
echo.
echo   4. Teste no PowerShell:
echo      python --version
echo      (deve aparecer algo como Python 3.12.x)
echo.
echo  Depois disso, execute este arquivo novamente.
echo ================================================================
pause
exit /b 1
