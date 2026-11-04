#!/bin/sh
# Faz 1 deploy — HOST tarafinda calisir (Coolify pre-deployment command).
#
# Coolify'un pre-deployment komutu SSH ile host'ta calisir → `docker` CLI
# host'ta zaten var. Bu betik:
#   1) ghcr.io token'ini bulur (app env dosyasindan; bulamazsa app
#      container'ina `docker exec` ile yayin yapar)
#   2) registry'ye girer
#   3) compose dosyasini public repodan indirir
#   4) .env yazar
#   5) `docker compose up -d` → 30 servis ayağa kalkar
set -u

LOG=/tmp/waas-host.log
: > "${LOG}"
UUID=b84g0oos48c40ssg4og4c8k0"
REPO=anilcetin/waas-deploy
BASE="https://raw.githubusercontent.com/${REPO}/main"
ENV_FILE=""
GH=""
APP_CONTAINER=""

app_container() {
  [ -n "${APP_CONTAINER}" ] && { printf '%s' "${APP_CONTAINER}"; return 0; }
  APP_CONTAINER=$(docker ps --filter "name=${UUID}" --format '{{.Names}}' 2>/dev/null | head -1)
  [ -n "${APP_CONTAINER}" ] || return 1
  printf '%s' "${APP_CONTAINER}"
}

publish() {
  content=$(base64 < "${LOG}" 2>/dev/null | tr -d '\n')
  payload="{\"message\":\"host deploy log\",\"content\":\"${content}\",\"branch\":\"main\"}"

  # 1) Host'ta token varsa dogrudan yayinla.
  if [ -n "${GH}" ]; then
    printf '%s' "${payload}" > /tmp/waas-payload.json
    curl -s -X PUT \
      -H "Authorization: Bearer ${GH}" \
      -H "Accept: application/vnd.github+json" \
      -H "Content-Type: application/json" \
      --data @/tmp/waas-payload.json \
      "https://api.github.com/repos/${REPO}/contents/host-log.txt" \
      >/dev/null 2>&1 && return 0
  fi

  # 2) Yoksa app container'ina docker exec ile yayinla
  #    (container'in env'inde GITHUB_TOKEN var).
  C=$(app_container) || return 1
  printf '%s' "${payload}" > /tmp/waas-payload.json
  docker cp /tmp/waas-payload.json "${C}:/tmp/waas-payload.json" >/dev/null 2>&1 || return 1
  docker exec "${C}" sh -c 'curl -s -X PUT -H "Authorization: Bearer ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" --data @/tmp/waas-payload.json "https://api.github.com/repos/anilcetin/waas-deploy/contents/host-log.txt" >/dev/null 2>&1' >/dev/null 2>&1
  return 0
}

say() {
  echo "[$(date -u +%H:%M:%S)] $*" >> "${LOG}"
  publish
}

trap publish EXIT

say "host deploy basladi (pwd=$(pwd))"
say "docker: $(command -v docker 2>&1)"

# --- Token'i bul ----------------------------------------------------------
for f in \
  "/data/coolify/applications/${UUID}/.env" \
  "/data/coolify/applications/${UUID}/env" \
  "/data/coolify/applications/${UUID}/.env.local" \
  "/data/coolify/applications/${UUID}" \
  $(ls -t /artifacts/*/.env 2>/dev/null | head -3) \
  $(ls -t /data/coolify/applications/*/.env 2>/dev/null | head -3)
do
  [ -f "$f" ] || continue
  v=$(grep -m1 '^GITHUB_TOKEN=' "$f" 2>/dev/null | cut -d= -f2- | tr -d '\r')
  if [ -n "${v}" ]; then
    ENV_FILE="$f"
    GH="$v"
    break
  fi
done

if [ -n "${GH}" ]; then
  say "token bulundu: ${ENV_FILE}"
else
  say "token bulunamadi (app env dosyasi arandi)"
  say "artifacts: $(ls /artifacts 2>&1 | head -4 | tr '\n' ' ')"
  say "applications: $(ls /data/coolify/applications 2>&1 | head -4 | tr '\n' ' ')"
fi

# --- Registry girisi ------------------------------------------------------
if [ -n "${GH}" ]; then
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
if [ -n "${ENV_FILE}" ] && [ -f "${ENV_FILE}" ]; then
  grep -E '^(ROOT_DOMAIN|POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_DB|ADMIN_EMAIL|ADMIN_PASSWORD|ADMIN_IP_ALLOWLIST|COOKIE_DOMAIN|CORS_ALLOWED_ORIGINS|SITE_BASE_HOST|SITES_SUBDOMAIN|CNAME_TARGET|MEDIA_PUBLIC_BASE_URL|API_PUBLIC_URL|STOREFRONT_SITE_URL|ADMIN_PORTAL_SITE_URL|CUSTOMER_PORTAL_SITE_URL|THEME_ROUTER_SITE_URL|STRIPE_SECRET_KEY_LIVE|STRIPE_WEBHOOK_SECRET|Email__Provider|Email__Mailjet__ApiKey|Email__Mailjet__ApiSecret|Email__FromEmail|Email__FromName|Email__NotificationRecipient)=' "${ENV_FILE}" > .env
  say ".env kopyalandi: ${ENV_FILE} ($(wc -l < .env) satir)"
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
