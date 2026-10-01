# Ubumwe Connect — Deployment Guide

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Local Development Setup](#2-local-development-setup)
3. [Environment Configuration](#3-environment-configuration)
4. [Database Setup](#4-database-setup)
5. [Running with Docker Compose](#5-running-with-docker-compose)
6. [Production Deployment](#6-production-deployment)
7. [Flutter App Build & Release](#7-flutter-app-build--release)
8. [SSL / HTTPS Configuration](#8-ssl--https-configuration)
9. [Monitoring & Logs](#9-monitoring--logs)
10. [Scaling](#10-scaling)

---

## 1. Prerequisites

### Server Requirements (Production)
- Ubuntu 22.04 LTS (or equivalent)
- 2 vCPUs, 4 GB RAM minimum (4 vCPUs, 8 GB recommended)
- 40 GB SSD storage
- Static IP address
- Domain name pointing to the server

### Local Development
- [Docker Desktop](https://www.docker.com/products/docker-desktop) v24+
- [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.24+
- Python 3.11+
- Git

### External Service Accounts Required
- **OpenAI** — for GPT-4o-mini (translation) and Whisper (STT)
- **Firebase** — for Auth and FCM push notifications
- **AWS** — for S3 file storage (optional; app works without media uploads)

---

## 2. Local Development Setup

### Clone the Repository

```bash
git clone https://github.com/yourorg/ubumweconnect.git
cd ubumweconnect
```

### Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Copy environment file
cp .env.example .env
# Edit .env with your values (see Section 3)
```

### Frontend Setup

```bash
cd frontend

# Install Flutter dependencies
flutter pub get

# Copy Firebase config (download from Firebase Console)
# Android: google-services.json → android/app/google-services.json
# iOS:     GoogleService-Info.plist → ios/Runner/GoogleService-Info.plist

# Copy environment
cp .env.example .env
# Set API_BASE_URL=http://localhost:8000
```

---

## 3. Environment Configuration

### Backend `.env`

```bash
# Application
SECRET_KEY=your-super-secret-key-minimum-32-chars   # openssl rand -hex 32
DEBUG=true
ALGORITHM=HS256
ACCESS_TOKEN_EXPIRE_MINUTES=30
REFRESH_TOKEN_EXPIRE_DAYS=30

# Database
DATABASE_URL=postgresql+asyncpg://ubumwe_user:ubumwe_pass@localhost:5432/ubumwe_db

# Redis
REDIS_URL=redis://:redis_pass@localhost:6379/0

# OpenAI
OPENAI_API_KEY=sk-...

# Firebase (paste the entire JSON content as a single string)
FIREBASE_CREDENTIALS_JSON={"type":"service_account","project_id":"...","private_key":"..."}

# AWS S3 (optional)
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_S3_BUCKET=ubumwe-uploads
AWS_S3_REGION=us-east-1

# CORS
CORS_ORIGINS=http://localhost:3000,http://localhost:8080
```

### Firebase Setup

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Create a project named "UbumweConnect"
3. Enable **Authentication** → Sign-in methods: Email/Password + Google
4. Download **Service Account** key:
   - Project Settings → Service Accounts → Generate New Private Key
   - Paste the JSON content into `FIREBASE_CREDENTIALS_JSON` env var
5. Register Android app with package name `rw.ubumweconnect.app`
6. Download `google-services.json` → place in `frontend/android/app/`
7. Enable **FCM** (Cloud Messaging) — auto-enabled with Firebase project

---

## 4. Database Setup

### Option A — Docker (Recommended)

```bash
# Start only PostgreSQL and Redis
docker compose -f deployment/docker/docker-compose.yml up -d postgres redis

# Wait for health checks to pass (30 seconds)
sleep 30

# Schema is auto-applied via docker-entrypoint-initdb.d scripts
# Seed data is also auto-applied
```

### Option B — Manual PostgreSQL

```bash
# Install PostgreSQL 16
sudo apt install postgresql-16

# Create database and user
sudo -u postgres psql <<EOF
CREATE USER ubumwe_user WITH PASSWORD 'ubumwe_pass';
CREATE DATABASE ubumwe_db OWNER ubumwe_user;
GRANT ALL PRIVILEGES ON DATABASE ubumwe_db TO ubumwe_user;
\c ubumwe_db
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
EOF

# Apply schema
psql -U ubumwe_user -d ubumwe_db -f database/schema.sql

# Apply seed data (optional)
psql -U ubumwe_user -d ubumwe_db -f database/seed_data.sql
```

### Running Alembic Migrations

```bash
cd backend

# Create migration
alembic revision --autogenerate -m "Add new table"

# Apply migrations
alembic upgrade head

# Check current revision
alembic current

# Rollback one revision
alembic downgrade -1
```

---

## 5. Running with Docker Compose

### Development (with hot-reload)

```bash
# Start all services
docker compose -f deployment/docker/docker-compose.yml up -d

# View logs
docker compose -f deployment/docker/docker-compose.yml logs -f backend

# Open pgAdmin (DB management)
docker compose -f deployment/docker/docker-compose.yml --profile dev-tools up -d pgadmin
# Access at: http://localhost:5050
# Login: admin@ubumwe.local / admin

# Stop all services
docker compose -f deployment/docker/docker-compose.yml down
```

### Verify Everything Is Running

```bash
# Check service health
docker compose ps

# Test API health endpoint
curl http://localhost:8000/health

# Expected response:
# {"status": "healthy", "database": "connected", "redis": "connected"}

# View API docs
open http://localhost:8000/api/v1/docs
```

---

## 6. Production Deployment

### Step 1 — Prepare the Server

```bash
# SSH into your server
ssh user@your-server-ip

# Run the setup script
sudo bash /path/to/deployment/scripts/setup.sh
```

The setup script automatically:
- Installs Docker, Nginx, Certbot
- Creates the app user
- Clones the repository
- Prompts for SSL certificate setup
- Starts all services

### Step 2 — Configure Environment

```bash
sudo nano /opt/ubumwe-connect/.env
# Fill in all production values
```

Key production settings:
```bash
DEBUG=false
SECRET_KEY=<generate with: openssl rand -hex 32>
DATABASE_URL=postgresql+asyncpg://...  # Use strong password
OPENAI_API_KEY=sk-...                   # Your actual key
CORS_ORIGINS=https://app.ubumweconnect.rw
```

### Step 3 — Deploy

```bash
cd /opt/ubumwe-connect

# Pull latest images
docker compose -f deployment/docker/docker-compose.yml \
               -f deployment/docker/docker-compose.prod.yml \
               pull

# Start/update services (zero-downtime rolling update)
docker compose -f deployment/docker/docker-compose.yml \
               -f deployment/docker/docker-compose.prod.yml \
               up -d

# Run migrations
bash deployment/scripts/migrate.sh
```

### Step 4 — Verify

```bash
# Check service health
curl https://api.ubumweconnect.rw/health

# Check WebSocket
# (Use a WebSocket testing tool like wscat)
wscat -c wss://api.ubumweconnect.rw/ws/test?token=invalid
# Should return 401 Unauthorized
```

### Automated Deployments

After initial setup, deployments are automated via GitHub Actions (`.github/workflows/ci-cd.yml`):
1. Push to `main` branch
2. CI runs tests
3. Docker image is built and pushed to GitHub Container Registry
4. Server pulls new image and restarts with rolling update

---

## 7. Flutter App Build & Release

### Android — Debug APK

```bash
cd frontend
flutter build apk --debug
# Output: build/app/outputs/flutter-apk/app-debug.apk
```

### Android — Release APK

```bash
# Create keystore (first time only)
keytool -genkey -v -keystore android/app/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

# Create android/key.properties:
cat > android/key.properties <<EOF
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=upload
storeFile=upload-keystore.jks
EOF

# Build release APK
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

### iOS — Archive (Mac only)

```bash
cd frontend
flutter build ipa
# Open Xcode and upload to App Store Connect
```

### Environment Configuration for Flutter

Create `frontend/.env`:
```
API_BASE_URL=https://api.ubumweconnect.rw
WS_BASE_URL=wss://api.ubumweconnect.rw
```

---

## 8. SSL / HTTPS Configuration

### Using Let's Encrypt (Certbot)

```bash
# Get initial certificate
sudo certbot --nginx -d api.ubumweconnect.rw -d app.ubumweconnect.rw

# Test auto-renewal
sudo certbot renew --dry-run
```

The `docker-compose.prod.yml` includes a Certbot service that auto-renews certificates every 12 hours.

### Nginx HTTPS Configuration

Update `deployment/nginx/nginx.conf` to add HTTPS:
```nginx
server {
    listen 443 ssl;
    server_name api.ubumweconnect.rw;

    ssl_certificate /etc/letsencrypt/live/api.ubumweconnect.rw/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.ubumweconnect.rw/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # ... rest of config
}
```

---

## 9. Monitoring & Logs

### Viewing Logs

```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f backend
docker compose logs -f postgres

# Last 100 lines
docker compose logs --tail=100 backend
```

### Log Files

```bash
# Nginx access logs
tail -f /var/lib/docker/volumes/ubumwe_nginx_logs/_data/access.log

# Application logs (structured JSON)
docker compose logs backend | jq .
```

### Health Checks

```bash
# API health
curl https://api.ubumweconnect.rw/health

# Database connection check
docker compose exec postgres pg_isready -U ubumwe_user -d ubumwe_db

# Redis check
docker compose exec redis redis-cli -a redis_pass ping
```

### Automated Backups

```bash
# Add to crontab (runs at 2 AM daily)
crontab -e
# Add line:
0 2 * * * /opt/ubumwe-connect/deployment/scripts/backup.sh >> /var/log/ubumwe-backup.log 2>&1
```

---

## 10. Scaling

### Vertical Scaling
Update Docker resource limits in `docker-compose.prod.yml`:
```yaml
deploy:
  resources:
    limits:
      memory: 2G
      cpus: "2.0"
```

### Horizontal Scaling
Run multiple backend replicas:
```yaml
backend:
  deploy:
    replicas: 4  # Nginx distributes load with least_conn
```

### Database Read Replicas
For high read load, add a PostgreSQL read replica and direct read-heavy endpoints to it.

### Redis Cluster
For high availability, replace single Redis with Redis Sentinel or Redis Cluster.

### Kubernetes
See `deployment/kubernetes/deployment.yaml` for Kubernetes manifests supporting:
- Horizontal Pod Autoscaler (HPA) based on CPU
- Pod Disruption Budget for zero-downtime deployments
- ConfigMap for environment variables
- Secret for sensitive keys
