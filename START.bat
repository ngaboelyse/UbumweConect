@echo off
title UbumweConnect - Backend Starter
echo.
echo  Starting UbumweConnect backend (Docker Desktop + containers)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ensure_backend.ps1"
echo.
echo  Backend is up. API docs: http://localhost:8000/docs
echo.
pause
