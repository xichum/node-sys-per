FROM alpine:latest

RUN apk add --no-cache \
    bash \
    curl \
    wget \
    openssl \
    ca-certificates \
    util-linux \
    grep \
    sed \
    coreutils \
    tzdata \
    && rm -rf /var/cache/apk/*

WORKDIR /app
COPY entrypoint.sh /app/run.sh
RUN chmod +x /app/run.sh
VOLUME ["/data"]

ENTRYPOINT ["/app/run.sh"]
