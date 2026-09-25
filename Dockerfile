FROM alpine:3.20

RUN apk add --no-cache zip

WORKDIR /workspace

COPY tools/package-mod.sh /usr/local/bin/package-mod
RUN chmod +x /usr/local/bin/package-mod

ENTRYPOINT ["package-mod"]
