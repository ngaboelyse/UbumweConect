#!/bin/bash
# ============================================================
# Ubumwe Connect — Database Migration Script
# ============================================================
set -euo pipefail

APP_DIR="/opt/ubumwe-connect"
cd "$APP_DIR"

echo "Running Alembic migrations..."
docker compose -f deployment/docker/docker-compose.yml \
               -f deployment/docker/docker-compose.prod.yml \
               exec -T backend alembic upgrade head

echo "Migration complete."
docker compose -f deployment/docker/docker-compose.yml \
               -f deployment/docker/docker-compose.prod.yml \
               exec -T backend alembic current
