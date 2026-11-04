#!/bin/sh
# Faz 1 deploy — HOST tarafinda calisir (Coolify pre-deployment command).
#
# Coolify'un pre-deployment komutu SSH ile host'ta calisir → `docker` CLI
# host'ta zaten var. Bu betik:
#   1) ghcr.io token'ini bulur (app env dosyasindan)
#   2) registry'ye girer
#   3) compose dosyasini public repodan indirir
#   4) .env yazar
#   5) `docker compose up -d` → 30 servis ayağa kalkar
#   6) logu GitHub'a yazar (token bulunduysa)
set -u

LOG=/tmp/waas-host.log
: > "${LOG}"
UUID=b84g0oos48c40ssg4og4c8k0"
REPO=anilcetin/waas-deploy
BASE="https://raw.githubusercontent.com/${REPO}/main"

# --- Token'i bul ----------------------------------------------------------
find_token() {
  for f in \
    "/data/coolify/applications/${UUID}/.env" \
    "/data/coolify/applications/${UUID}/env" \
    "/data/coolify/applications/${UUID}/.env.local" \
    $(ls -t /artifacts/*/.env 2>/dev/null | head -3) \
    $(ls -t /data/coolify/applications/*/.env 2>/dev/null | head -3)
  do
    [ -f "$f" ] || continue
    v=$(grep -m1 '^GITHUB_TOKEN=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"'\r')
    if [ -n "${v:-}" ]; then
      ENV_FILE="$f"
      printf '%s' "$v"
      return 0
    fi
  done
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    ENV_FILE="(environment)"
    printf '%s' "$GITHUB_TOKEN"
    return 0
  fi
  return 1
}

publish() {
  [ -n "${GH:-}" ] || return 0
  content=$(base64 < "${LOG}" 2>/dev/null | tr -d '\n')
  printf '{"message":"host deploy log","content":"%s","branch":"main"}' "${content}" > /tmp/waas-payload.json
  curl -s -X PUT \
    -H "Authorization: Bearer ${GH}" \
    -H "Accept: application/vnd.github+json" \
    -H "Content-Type: application/json" \
    --data @/tmp/waas-payload.json \
    "https://api.github.com/repos/${REPO}/contents/host-log.txt" \
    >/dev/null 2>&1 || true
}

say() {
  echo "[$(date -u +%H:%M:%S)] $*" >> "${LOG}"
  publish
}

trap publish EXIT

say "host deploy basladi (pwd=$(pwd))"
say "docker: $(command -v docker 2>&1)"

GH=$(find_token)
if [ -n "${GH:-}" ]; then
  say "token bulundu: ${ENV_FILE}"
  export GH
else
  say "token bulunamadi (app env dosyasini aradim)"
fi

# --- Registry girisi ------------------------------------------------------
if [ -n "${GH:-}" ]; then
  printf '%s' "$GH" | docker login ghcr.io -u anilcetin --password-stdin >> "${LOG}" 2>&1
  say "docker login sonucu: $?"
fi

# --- Compose dosyasi ------------------------------------------------------
mkdir -p /opt/waas/postgres-init
cd /opt/waas || exit 1
curl -s -o compose.yml "${BASE}/compose.yml"
say "compose indirildi: $(wc -c < compose.yml) bayt"
curl -s -o postgres-init/01-extensions.sql "${BASE}/postgres-init/01-extensions.sql"
say "postgres-init indirildi: $(wc -c < postgres-init/01-extensions.sql) bayt"

# --- .env -----------------------------------------------------------------
ENV_FILE_USED="${ENV_FILE:-}"
if [ -n "${ENV_FILE_USED}" ] && [ -f "${ENV_FILE_USED}" ]; then
  grep -E '^(ROOT_DOMAIN|POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_DB|ADMIN_EMAIL|ADMIN_PASSWORD|ADMIN_IP_ALLOWLIST|COOKIE_DOMAIN|CORS_ALLOWED_ORIGINS|SITE_BASE_HOST|SITES_SUBDOMAIN|CNAME_TARGET|MEDIA_PUBLIC_BASE_URL|API_PUBLIC_URL|STOREFRONT_SITE_URL|ADMIN_PORTAL_SITE_URL|CUSTOMER_PORTAL_SITE_URL|THEME_ROUTER_SITE_URL|STRIPE_SECRET_KEY_LIVE|STRIPE_WEBHOOK_SECRET|Email__Provider|Email__Mailjet__ApiKey|Email__Mailjet__ApiSecret|Email__FromEmail|Email__FromName|Email__NotificationRecipient)=' "${ENV_FILE_USED}" > .env
  say ".env kopyalandi: ${ENV_FILE_USED} ($(wc -l < .env) satir)"
else
  cat > .env <<EOF
ROOT_DOMAIN=webyono.com
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
POSTGRES_DB=waas_prod
POSTGRES_INIT_DIR=/opt/waas/postgres-init
ADMIN_EMAIL=admin@webyono.com
ADMIN_PASSWORD=CHANGE_ME
ADMIN_IP_ALLOWLIST=
COOKIE_DOMAIN=webyono.com
CORS_ALLOWED_ORIGINS=https://webyono.com,https://www.webyono.com,https://admin.webyono.com,https://app.webyono.com
SITE_BASE_HOST=webyono.com
SITES_SUBDOMAIN=sites
CNAME_TARGET=sites.webyono.com
MEDIA_PUBLIC_BASE_URL=https://api.webyono.com/media
API_PUBLIC_URL=https://api.webyono.com
STOREFRONT_SITE_URL=https://webyono.com
ADMIN_PORTAL_SITE_URL=https://admin.webyono.com
CUSTOMER_PORTAL_SITE_URL=https://app.webyono.com
THEME_ROUTER_SITE_URL=https://sites.webyono.com
STRIPE_SECRET_KEY_LIVE=
STRIPE_WEBHOOK_SECRET=
Email__Provider=Console
Email__Mailjet__ApiKey=
Email__Mailjet__ApiSecret=
Email__FromEmail=no-reply@webyono.com
Email__FromName=WebYono
Email__NotificationRecipient=ops@webyono.com
EOF
  say ".env varsayilanlarla yazildi"
fi

# --- Ag -------------------------------------------------------------------
docker network inspect coolify >/dev/null 2>&1 || docker network create coolify >/dev/null
say "ag hazir"

# --- Imajlari cek ---------------------------------------------------------
attempt=0
until docker compose --env-file /opt/waas/.env -f /opt/waas/compose.yml pull >> "${LOG}" 2>&1; do
  attempt=$((attempt + 1))
  if [ "${attempt}" -ge 60 ]; then
    say "imaj cekme basarisiz (60 deneme)"
    break
  fi
  say "imajlar hazir degil, tekrar deneniyor (${attempt}/60)"
  sleep 20
done
say "imaj cekme bitti"

# --- Ayağa kaldir ---------------------------------------------------------
docker compose --env-file /opt/waas/.env -f /opt/waas/compose.yml up -d --remove-orphans >> "${LOG}" 2>&1
say "compose up cikisi: $?"

docker compose --env-file /opt/waas/.env -f /opt/waas/compose.yml ps >> "${LOG}" 2>&1
say "TAMAMLANDI"
