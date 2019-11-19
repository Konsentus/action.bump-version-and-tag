FROM alpine:latest

ADD entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash git

ENTRYPOINT ["/entrypoint.sh"]
