FROM golang:alpine AS Builder

ARG path=selks

RUN mkdir -p /src
# hadolint ignore=DL3018
RUN apk update && apk add --no-cache gcc musl-dev make

COPY /bin/$path /src/.
WORKDIR /src

RUN CGO_ENABLED=1 make

FROM busybox:1.37 as BUNDLE

ARG path=selks
ARG TEMPLATE_VERSION=1.0.0

COPY /data/$path /data
# printf, not echo: echo appends a trailing newline, which leaked into the
# baked version file (1.2.0 -> "1.2.0\n") and downstream into stamusctl.
RUN printf '%s' "${TEMPLATE_VERSION}" > /data/version
COPY --from=Builder /src/dist /sbin/

ENTRYPOINT [ "bin/sh", "-c" ]