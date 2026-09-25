FROM alpine:3.20

RUN apk add --no-cache zip

WORKDIR /workspace

COPY tools/package-mod.sh /usr/local/bin/package-mod
RUN sed -i 's/\r$//' /usr/local/bin/package-mod \
    && chmod +x /usr/local/bin/package-mod

ENTRYPOINT ["/bin/sh", "/usr/local/bin/package-mod"]
