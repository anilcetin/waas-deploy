#!/bin/sh
# Faz 1 bootstrap — Coolify uygulamasi olarak calisir.
# Docker socket uzerinden host daemon'ina baglanir ve prod compose'u
# ayağa kaldirir.
set -eu

REPO='anilcetin/business-platform'
BRANCH='main'
BASE="https://api.github.com/repos/${REPO}/contents"
GH_USER='anilcetin'
WORK=/tmp/waas

echo "[bootstrap] basladi"

mkdir -p "${WORK}" /host/waas/postgres-init

# --- 1) Postgres init betigi (host'a kopyala) ---------------------------
cp /app/postgres-init/*.sql /host/waas/postgres-init/ 2>/dev/null || true
echo "[bootstrap] postgres-init kopyalandi"

# --- 2) Registry girisi --------------------------------------------------
echo "${GITHUB_TOKEN}" | docker login ghcr.io -u "${GH_USER}" --password-stdin
echo "[bootstrap] ghcr.io girisi tamam"

# --- 3) .env (compose icin) ---------------------------------------------
cat > "${WORK}/.env" <<EOF
ROOT_DOMAIN=${ROOT_DOMAIN}
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=${POSTGRES_DB}
POSTGRES_INIT_DIR=/opt/waas/postgres-init
ADMIN_EMAIL=${ADMIN_EMAIL}
ADMIN_PASSWORD=${ADMIN_PASSWORD}
ADMIN_IP_ALLOWLIST=${ADMIN_IP_ALLOWLIST}
COOKIE_DOMAIN=${COOKIE_DOMAIN}
CORS_ALLOWED_ORIGINS=${CORS_ALLOWED_ORIGINS}
SITE_BASE_HOST=${SITE_BASE_HOST}
SITES_SUBDOMAIN=${SITES_SUBDOMAIN}
CNAME_TARGET=${CNAME_TARGET}
MEDIA_PUBLIC_BASE_URL=${MEDIA_PUBLIC_BASE_URL}
API_PUBLIC_URL=${API_PUBLIC_URL}
STOREFRONT_SITE_URL=${STOREFRONT_SITE_URL}
ADMIN_PORTAL_SITE_URL=${ADMIN_PORTAL_SITE_URL}
CUSTOMER_PORTAL_SITE_URL=${CUSTOMER_PORTAL_SITE_URL}
THEME_ROUTER_SITE_URL=${THEME_ROUTER_SITE_URL}
STRIPE_SECRET_KEY_LIVE=${STRIPE_SECRET_KEY_LIVE}
STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}
Email__Provider=${Email__Provider}
Email__Mailjet__ApiKey=${Email__Mailjet__ApiKey}
Email__Mailjet__ApiSecret=${Email__Mailjet__ApiSecret}
Email__FromEmail=${Email__FromEmail}
Email__FromName=${Email__FromName}
Email__NotificationRecipient=${Email__NotificationRecipient}
EOF
echo "[bootstrap] .env yazildi"

# --- 4) Ag ---------------------------------------------------------------
docker network inspect coolify >/dev/null 2>&1 || docker network create coolify >/dev/null

# --- 5) Imajlari cek -----------------------------------------------------
attempt=0
until docker compose --env-file "${WORK}/.env" -f "${WORK}/compose.yml" pull; do
  attempt=$((attempt + 1))
  if [ "${attempt}" -ge 90 ]; then
    echo "[bootstrap] imaj cekme basarisiz"
    exit 1
  fi
  echo "[bootstrap] imajlar hazir degil, tekrar deneniyor (${attempt}/90)"
  sleep 20
done
echo "[bootstrap] imajlar cekildi"

# --- 6) Ayağa kaldir ------------------------------------------------------
docker compose --env-file "${WORK}/.env" -f "${WORK}/compose.yml" up -d --remove-orphans
docker compose --env-file "${WORK}/.env" -f "${WORK}/compose.yml" ps

echo "[bootstrap] TAMAMLANDI"

# Container ayakta kalsin (yeniden deploy mumkun olsun).
exec tail -f /dev/null
