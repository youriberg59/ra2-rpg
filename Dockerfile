FROM node:20-bookworm

ARG RA2WEB_REPO=https://github.com/DD-Channel/ra2-web.git
ARG RA2WEB_COMMIT=786800b50fe19f7dbe1fa6243e364fd761c64198

RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN git clone "$RA2WEB_REPO" . \
 && git checkout "$RA2WEB_COMMIT"

RUN sed -i "s#../../util/Logger#../../util/logger#g" src/engine/gameRes/GameRes.ts \
 && npm ci

COPY docker/start-ra2web.sh /usr/local/bin/start-ra2web
RUN sed -i 's/\r$//' /usr/local/bin/start-ra2web \
 && chmod +x /usr/local/bin/start-ra2web

EXPOSE 3000

ENTRYPOINT ["/bin/sh", "/usr/local/bin/start-ra2web"]
