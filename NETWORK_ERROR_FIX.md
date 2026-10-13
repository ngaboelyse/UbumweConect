# 🔧 NETWORK ERROR FIX - XMLHttpRequest Connection Error

## Problem
**Error Message:**
```
The connection errored. The XMLHttpRequest onError callback was called.
This typically indicates an error on the network layer.
```

## Root Cause
The Flutter web frontend was trying to connect to the backend API at `http://localhost:8000/api/v1`, but the backend server was **NOT running**.

---

## ✅ Solution - Quick Start

### Step 1️⃣: **Start All Services**

**Windows (PowerShell):**
```powershell
cd d:\ALL\Project\UbumweConnect
.\START_DEVELOPMENT.ps1
```

**Windows (Command Prompt):**
```cmd
cd d:\ALL\Project\UbumweConnect
START_DEVELOPMENT.bat
```

This will:
- ✅ Start PostgreSQL database container
- ✅ Start Redis cache container  
- ✅ Start FastAPI backend server
- ✅ Initialize database schema

Wait ~15 seconds for services to fully initialize.

---

### Step 2️⃣: **Verify Backend is Running**

Open a browser and navigate to:
```
http://localhost:8000/docs
```

You should see the **Swagger UI** with all API endpoints. If you see this, the backend is ready! ✅

---

### Step 3️⃣: **Start Flutter Frontend** (in a NEW terminal)

**For Web (Chrome/Edge):**
```powershell
cd d:\ALL\Project\UbumweConnect\frontend
flutter clean
flutter pub get
flutter run -d chrome
```

**For Windows Desktop:**
```powershell
cd d:\ALL\Project\UbumweConnect\frontend
flutter clean
flutter pub get
flutter run -d windows
```

---

## 🔍 Detailed Setup Instructions

### Backend Configuration

The backend is pre-configured in `backend/.env`:
- **API Port:** 8000
- **Database:** PostgreSQL (5432)
- **Cache:** Redis (6379)
- **API Base URL:** `/api/v1`

### Frontend Configuration

The frontend is pre-configured in `frontend/lib/core/constants/app_constants.dart`:
```dart
static const String baseUrl = 'http://localhost:8000/api/v1';
static const String wsBaseUrl = 'ws://localhost:8000/ws';
```

This matches the backend exactly! ✅

### CORS Configuration

**Backend CORS Policy** (app/main.py):
```python
allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$"
```

✅ Allows requests from:
- `http://localhost:*` (any port)
- `http://127.0.0.1:*` (any port)

This covers all development scenarios! ✅

---

## 🚀 Service Ports Reference

| Service | URL | Purpose |
|---------|-----|---------|
| **FastAPI Backend** | `http://localhost:8000` | REST API + WebSocket |
| **API Documentation** | `http://localhost:8000/docs` | Interactive Swagger UI |
| **PostgreSQL** | `postgresql://localhost:5432` | Database |
| **Redis** | `redis://localhost:6379` | Cache/Session Store |
| **Flutter Web App** | `http://localhost:3000` | Frontend (when running) |

---

## ❌ Troubleshooting

### Issue: "Could not connect to Docker daemon"

**Solution:**
```powershell
# Start Docker Desktop
# OR verify it's running
docker ps
```

### Issue: "Port 8000 already in use"

**Solution:**
```powershell
# Find what's using port 8000
netstat -ano | findstr :8000

# Kill the process (replace PID with the actual number)
taskkill /PID <PID> /F

# OR change the backend port in docker-compose.yml
# Change '8000:8000' to '8001:8000'
```

### Issue: "Flutter can't connect to backend"

**Checklist:**
- [ ] Docker containers running? → `docker ps`
- [ ] Backend logs OK? → `docker logs ubumwe_backend`
- [ ] Can reach API? → Open `http://localhost:8000/docs` in browser
- [ ] CORS enabled? → Should see swagger API docs
- [ ] Frontend app reloaded? → Hard refresh (Ctrl+Shift+R)

### Issue: "Database connection error"

**Solution:**
```powershell
# Check if PostgreSQL is running
docker logs ubumwe_postgres

# Restart all services
cd deployment/docker
docker-compose down
docker-compose up -d
```

### Issue: "Redis connection error"

**Solution:**
```powershell
# Check if Redis is running
docker logs ubumwe_redis

# Clear Redis data if corrupted
docker exec ubumwe_redis redis-cli FLUSHALL
```

---

## 📊 Service Status Commands

```powershell
# Check all containers
docker ps

# View specific service logs
docker logs ubumwe_backend
docker logs ubumwe_postgres
docker logs ubumwe_redis

# Check backend API health
Invoke-WebRequest -Uri http://localhost:8000/health

# Check if port is listening
netstat -ano | findstr :8000

# Stop all services
cd deployment/docker
docker-compose down

# Stop and remove all data (CAREFUL!)
docker-compose down -v
```

---

## 🔄 Full Recovery Steps (Nuclear Option)

If everything is broken, start fresh:

```powershell
# Stop everything
cd d:\ALL\Project\UbumweConnect\deployment\docker
docker-compose down -v

# Remove all images
docker rmi -f ubumwe_postgres ubumwe_redis ubumwe_backend

# Clear Docker system
docker system prune -a -f

# Start fresh
docker-compose up -d

# Wait 30 seconds
Start-Sleep -Seconds 30

# Check status
docker ps
```

---

## ✅ Verification Checklist

After starting services, verify everything works:

- [ ] **Backend Responsive** → `Invoke-WebRequest http://localhost:8000/docs`
- [ ] **Database Connected** → `docker logs ubumwe_backend` shows "Database connected"
- [ ] **Redis Active** → `docker logs ubumwe_redis` shows no errors
- [ ] **API Docs Visible** → See Swagger UI at localhost:8000/docs
- [ ] **Flutter App Loads** → No network errors in console
- [ ] **Can Login** → Try creating test account or using demo credentials

---

## 📝 Common Tasks

### View Backend Logs
```powershell
docker logs -f ubumwe_backend
```

### Access Database CLI
```powershell
docker exec -it ubumwe_postgres psql -U ubumwe_user -d ubumwe_db
```

### Clear All Caches
```powershell
docker exec ubumwe_redis redis-cli FLUSHALL
```

### Restart Backend Only
```powershell
docker restart ubumwe_backend
```

### Build Backend Docker Image
```powershell
cd deployment/docker
docker-compose down
docker build -t ubumwe-backend:local ../..
docker-compose up -d
```

---

## 🎯 Next Steps

1. ✅ Run `.\START_DEVELOPMENT.ps1`
2. ✅ Wait for all containers to be "Healthy" 
3. ✅ Open `http://localhost:8000/docs` 
4. ✅ In a NEW terminal, run `flutter run -d chrome`
5. ✅ App should now load without network errors!

---

## 📚 For More Help

- Backend Documentation: `docs/DEPLOYMENT_GUIDE.md`
- Frontend Flow Guide: `FRONTEND_FLOW_GUIDE.md`
- API Docs (when running): `http://localhost:8000/docs`

