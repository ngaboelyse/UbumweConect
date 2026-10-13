@echo off
REM ============================================================
REM Ubumwe Connect - Quick Start Script
REM ============================================================
REM This script starts all required services for development

setlocal enabledelayedexpansion

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║         Ubumwe Connect - Development Environment         ║
echo ║      Starting Backend, Database, and Frontend...         ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.

REM Check if Docker is running
docker --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Docker is not installed or not running!
    echo Please install Docker Desktop from: https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

echo ✅ Docker is available

REM Check if Docker daemon is running
docker ps >nul 2>&1
if errorlevel 1 (
    echo ❌ Docker daemon is not running!
    echo Please start Docker Desktop and try again.
    pause
    exit /b 1
)

echo ✅ Docker daemon is running

REM Start database and redis
echo.
echo 📦 Starting PostgreSQL and Redis containers...
cd /d "%~dp0deployment\docker"
docker-compose up -d

echo.
echo ⏳ Waiting 15 seconds for database to initialize...
timeout /t 15 /nobreak

REM Check if backend needs to be started
docker ps | findstr ubumwe_backend >nul 2>&1
if errorlevel 1 (
    echo ⚠️  Backend container not running
    echo 🚀 You can optionally start backend with: docker-compose up -d ubumwe_backend
)

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║                  SERVICES RUNNING                         ║
echo ╠═══════════════════════════════════════════════════════════╣
echo ║  🗄️  PostgreSQL Database:  postgresql://localhost:5432   ║
echo ║  💾 Redis Cache:           redis://localhost:6379        ║
echo ║  🚀 FastAPI Backend:       http://localhost:8000         ║
echo ║  📚 API Docs (Swagger):    http://localhost:8000/docs    ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.

echo To complete the setup, open a NEW terminal and run:
echo.
echo   cd frontend
echo   flutter run -d chrome
echo.
echo Or for Windows desktop:
echo   flutter run -d windows
echo.

pause
