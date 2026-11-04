FROM docker:27-cli
RUN apk add --no-cache curl git openssh-client bash

WORKDIR /app
COPY compose.yml /app/compose.yml
COPY postgres-init/ /app/postgres-init/
COPY bootstrap.sh /app/bootstrap.sh
RUN chmod +x /app/bootstrap.sh

# Build asamasinda socket kontrolu (sonuc GitHub'a yazilir).
RUN set -eux; \
    if [ -S /var/run/docker.sock ]; then SOCK=YES; else SOCK=NO; fi; \
    if command -v docker >/dev/null 2>&1; then CLI=$(command -v docker); else CLI=none; fi; \
    if docker info >/dev/null 2>&1; then DAEMON=OK; else DAEMON=FAIL; fi; \
    printf '{"message":"build probe","content":"%s","branch":"main"}' \
      "$(printf 'socket=%s cli=%s daemon=%s\n' "$SOCK" "$CLI" "$DAEMON" | base64 | tr -d '\n')" \
      > /tmp/probe.json; \
    curl -s -X PUT -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
      --data @/tmp/probe.json \
      "https://api.github.com/repos/anilcetin/waas-deploy/contents/build-probe.txt" \
      >/dev/null 2>&1 || true; \
    echo "probe: socket=$SOCK cli=$CLI daemon=$DAEMON"

ENTRYPOINT ["/app/bootstrap.sh"]
