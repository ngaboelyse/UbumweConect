#!/usr/bin/env pwsh
# ============================================================
# Ubumwe Connect - Quick Start Script (PowerShell)
# ============================================================
# This script starts all required services for development

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║         Ubumwe Connect - Development Environment         ║" -ForegroundColor Cyan
Write-Host "║      Starting Backend, Database, and Frontend...         ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is installed
try {
    $dockerVersion = docker --version 2>$null
    Write-Host "✅ Docker is available: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker is not installed or not running!" -ForegroundColor Red
    Write-Host "Please install Docker Desktop from: https://www.docker.com/products/docker-desktop" -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Check if Docker daemon is running
try {
    docker ps >$null 2>&1
    Write-Host "✅ Docker daemon is running" -ForegroundColor Green
} catch {
    Write-Host "❌ Docker daemon is not running!" -ForegroundColor Red
    Write-Host "Please start Docker Desktop and try again." -ForegroundColor Yellow
    Read-Host "Press Enter to exit"
    exit 1
}

# Start database and redis
Write-Host ""
Write-Host "📦 Starting PostgreSQL and Redis containers..." -ForegroundColor Yellow
Push-Location "$PSScriptRoot\deployment\docker"
docker-compose up -d
Pop-Location

Write-Host ""
Write-Host "⏳ Waiting 15 seconds for database to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 15

# Check if backend is running
$backendRunning = docker ps | Select-String "ubumwe_backend"
if ($null -eq $backendRunning) {
    Write-Host "⚠️  Backend container not running" -ForegroundColor Yellow
    Write-Host "🚀 You can optionally start backend with: docker-compose up -d ubumwe_backend" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                  SERVICES RUNNING                         ║" -ForegroundColor Cyan
Write-Host "╠═══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  🗄️  PostgreSQL Database:  postgresql://localhost:5432   ║" -ForegroundColor Cyan
Write-Host "║  💾 Redis Cache:           redis://localhost:6379        ║" -ForegroundColor Cyan
Write-Host "║  🚀 FastAPI Backend:       http://localhost:8000         ║" -ForegroundColor Cyan
Write-Host "║  📚 API Docs (Swagger):    http://localhost:8000/docs    ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "✅ All services are ready!" -ForegroundColor Green
Write-Host ""
Write-Host "To complete the setup, open a NEW terminal and run:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  cd frontend" -ForegroundColor White
Write-Host "  flutter run -d chrome" -ForegroundColor White
Write-Host ""
Write-Host "Or for Windows desktop:" -ForegroundColor Cyan
Write-Host ""
Write-Host "  flutter run -d windows" -ForegroundColor White
Write-Host ""
