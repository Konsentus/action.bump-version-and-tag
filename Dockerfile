FROM alpine:latest

COPY lib/semver ./lib/semver
RUN install ./lib/semver /usr/local/bin
COPY entrypoint.sh /entrypoint.sh

RUN apk add --no-cache bash git

# ENTRYPOINT ["/entrypoint.sh"]
