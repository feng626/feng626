FROM alpine:3.20

RUN apk add --no-cache curl keepalived

ENTRYPOINT ["/usr/sbin/keepalived", "--dont-fork", "--log-console"]
