FROM alpine:latest

COPY lib/semver.sh ./lib/semver
RUN install ./lib/semver /usr/local/bin
COPY entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash git jq
RUN apk add --no-cache hub --repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing

ENTRYPOINT ["/entrypoint.sh"]
