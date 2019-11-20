FROM alpine:latest

COPY lib/semver.sh ./lib/semver.sh
RUN install ./lib/semver.sh /usr/local/bin
COPY entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash git

ENTRYPOINT ["/entrypoint.sh"]
