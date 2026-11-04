#!/bin/sh
# Faz 1 bootstrap — Coolify uygulamasi olarak calisir.
#
# Docker socket uzerinden host daemon'ina baglanir ve prod compose'u
# ayağa kaldirir. Tum adimlar GitHub'a log olarak yazilir (public repo)
# → ag üzerinden log okunamasa bile durum görülebilir.
set -u

LOG=/tmp/waas-bootstrap.log
: > "${LOG}"

publish() {
  content=$(base64 < "${LOG}" 2>/dev/null | tr -d '\n')
  printf '{"message":"bootstrap log","content":"%s","branch":"main"}' "${content}" > /tmp/waas-payload.json
  curl -s -X PUT \
    -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    --data @/tmp/waas-payload.json \
    "https://api.github.com/repos/anilcetin/waas-deploy/contents/bootstrap.log" \
    >/dev/null 2>&1 || true
}

say() {
  echo "[$(date -u +%H:%M:%S)] $*" >> "${LOG}"
  publish
}

trap publish EXIT

say "bootstrap basladi"
say "docker socket: $(ls -la /var/run/docker.sock 2>&1 | head -1)"
say "docker CLI: $(command -v docker 2>&1)"
say "compose surumu: $(docker compose version 2>&1 | head -1)"

mkdir -p /tmp/waas /host/waas/postgres-init
cp /app/postgres-init/*.sql /host/waas/postgres-init/ 2>/dev/null || true
say "postgres-init kopyalandi"

echo "${GITHUB_TOKEN}" | docker login ghcr.io -u anilcetin --password-stdin >> "${LOG}" 2>&1
say "ghcr.io giris sonucu: $?"

cat > /tmp/waas/.env <<EOF
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
say ".env yazildi"

docker network inspect coolify >/dev/null 2>&1 || docker network create coolify >/dev/null
say "ag hazir"

attempt=0
until docker compose --env-file /tmp/waas/.env -f /app/compose.yml pull >> "${LOG}" 2>&1; do
  attempt=$((attempt + 1))
  if [ "${attempt}" -ge 90 ]; then
    say "imaj cekme basarisiz (90 deneme)"
    break
  fi
  say "imajlar hazir degil, tekrar deneniyor (${attempt}/90)"
  sleep 20
done
say "imaj cekme bitti"

docker compose --env-file /tmp/waas/.env -f /app/compose.yml up -d --remove-orphans >> "${LOG}" 2>&1
say "compose up cikisi: $?"

docker compose --env-file /tmp/waas/.env -f /app/compose.yml ps >> "${LOG}" 2>&1
say "TAMAMLANDI"

exec tail -f /dev/null
