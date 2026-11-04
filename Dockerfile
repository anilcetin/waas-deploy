FROM docker:27-cli
RUN apk add --no-cache curl git openssh-client bash

WORKDIR /app
COPY compose.yml /app/compose.yml
COPY postgres-init/ /app/postgres-init/
COPY bootstrap.sh /app/bootstrap.sh
RUN chmod +x /app/bootstrap.sh

ENTRYPOINT ["/app/bootstrap.sh"]
