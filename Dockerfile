ARG BASE_IMAGE
FROM ${BASE_IMAGE}

ARG OS
ARG ARCH
ARG BIN

ADD bin/${OS}_${ARCH}/${BIN} /${BIN}
ENV ARG_BIN="${BIN}"

# This would be nicer as `nobody:nobody` but distroless has no such entries.
USER 65535:65535

ENTRYPOINT exec "/${ARG_BIN}"
