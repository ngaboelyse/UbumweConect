#!/bin/bash
# ============================================================
# Ubumwe Connect - Initial Setup Script
# Run once on a fresh server to set up the environment
# ============================================================
set -euo pipefail

REPO_URL="https://github.com/yourorg/ubumweconnect.git"
APP_DIR="/opt/ubumwe-connect"
APP_USER="ubumwe"

echo "=================================================="
echo "  Ubumwe Connect — Server Setup"
echo "=================================================="

# Check root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: Please run as root (sudo $0)"
  exit 1
fi

echo "[1/8] Installing system dependencies..."
apt-get update -qq
apt-get install -y -qq \
  docker.io \
  docker-compose-v2 \
  git \
  curl \
  nginx \
  certbot \
  python3-certbot-nginx \
  ufw \
  fail2ban

echo "[2/8] Configuring firewall..."
ufw --force enable
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS

echo "[3/8] Creating app user..."
if ! id "$APP_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$APP_USER"
  usermod -aG docker "$APP_USER"
fi

echo "[4/8] Cloning repository..."
if [ ! -d "$APP_DIR" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

echo "[5/8] Setting up environment variables..."
if [ ! -f "$APP_DIR/.env" ]; then
  cp "$APP_DIR/.env.example" "$APP_DIR/.env"
  echo ""
  echo "==> IMPORTANT: Edit $APP_DIR/.env with your real values:"
  echo "    - SECRET_KEY (generate with: openssl rand -hex 32)"
  echo "    - OPENAI_API_KEY"
  echo "    - DATABASE credentials"
  echo "    - FIREBASE_CREDENTIALS_JSON"
  echo "    - AWS credentials"
  echo ""
fi

echo "[6/8] Setting up SSL (Let's Encrypt)..."
read -p "Enter your domain name (e.g. api.ubumweconnect.rw): " DOMAIN
if [ -n "$DOMAIN" ]; then
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m admin@"$DOMAIN" || true
fi

echo "[7/8] Starting services..."
cd "$APP_DIR"
su -c "docker compose -f deployment/docker/docker-compose.yml -f deployment/docker/docker-compose.prod.yml up -d" "$APP_USER"

echo "[8/8] Running database migrations..."
sleep 10  # Wait for DB to be ready
su -c "docker compose exec backend alembic upgrade head" "$APP_USER"

echo ""
echo "=================================================="
echo "  Setup complete!"
echo "  Backend: http://$DOMAIN/api/v1/docs"
echo "  Health:  http://$DOMAIN/health"
echo "=================================================="
