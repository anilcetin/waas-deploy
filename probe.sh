#!/bin/sh
# Coolify pre-deployment komutu icin teşhis betiği.
# Nerede çalıştığını ve ortamı raporlar → GitHub'a yazar.
set -u

OUT=/tmp/probe.txt
{
  echo "=== kimlik ==="
  echo "pwd: $(pwd)"
  echo "hostname: $(hostname)"
  echo "id: $(id 2>&1)"
  echo "date: $(date -u)"
  echo "=== docker socket ==="
  ls -la /var/run/docker.sock 2>&1 | head -2
  echo "=== docker info ==="
  docker info 2>&1 | head -5
  echo "=== env (anahtarlar) ==="
  env | cut -d= -f1 | sort | head -40
  echo "=== GITHUB_TOKEN var mi ==="
  if [ -n "${GITHUB_TOKEN:-}" ]; then echo "EVET (${#GITHUB_TOKEN} karakter)"; else echo "HAYIR"; fi
  echo "=== /app icerigi ==="
  ls /app 2>&1 | head -8
  echo "=== /data/coolify ==="
  ls /data/coolify 2>&1 | head -8
  echo "=== /artifacts ==="
  ls /artifacts 2>&1 | head -8
  echo "=== kok dosya sistemi ==="
  ls / 2>&1 | head -20
} > "${OUT}" 2>&1

content=$(base64 < "${OUT}" | tr -d '\n')
printf '{"message":"probe","content":"%s","branch":"main"}' "${content}" > /tmp/probe-payload.json
curl -s -X PUT \
  -H "Authorization: Bearer ${GITHUB_TOKEN:-none}" \
  -H "Accept: application/vnd.github+json" \
  -H "Content-Type: application/json" \
  --data @/tmp/probe-payload.json \
  "https://api.github.com/repos/anilcetin/waas-deploy/contents/probe.txt" \
  >/dev/null 2>&1 || true

echo "probe yazildi"
