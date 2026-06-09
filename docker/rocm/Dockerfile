ARG ROCM_IMAGE=rocm/dev-ubuntu-22.04:6.3
FROM ${ROCM_IMAGE}

ARG PYTHON_VERSION=3.12
ARG TARGETARCH
ARG XFORCE_USER=user
ARG XFORCE_UID=1000
ARG XFORCE_GID=1000
ARG WORKSPACE_DIR=/workspace
ARG VENV_DIR=/venv/main
ARG ENABLE_NUSHELL=1
ARG ENABLE_PORTAL=1
ARG ENABLE_CLOUDFLARED=0
ARG XFORCE_IMAGE_VERSION=dev
ARG XFORCE_IMAGE_REVISION=unknown
ARG XFORCE_IMAGE_SOURCE=https://github.com/xforce-ai/xforce-ai
ARG XFORCE_IMAGE_CREATED=unknown
ARG NUSHELL_VERSION=0.113.1
ARG NUSHELL_SHA256_AMD64=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb
ARG NUSHELL_SHA256_ARM64=08b94c6fd9c66881616df4c89adc03e8a42a57fdf6876cfd1b16cec7e82348b4
ARG CLOUDFLARED_VERSION=2025.6.0
ARG CLOUDFLARED_SHA256_AMD64=
ARG CLOUDFLARED_SHA256_ARM64=
ARG ROCM_VERSION=6.3

ENV DEBIAN_FRONTEND=noninteractive \
    XFORCE_IMAGE_VARIANT=rocm \
    XFORCE_IMAGE_VERSION=${XFORCE_IMAGE_VERSION} \
    XFORCE_USER=${XFORCE_USER} \
    ENABLE_NUSHELL=${ENABLE_NUSHELL} \
    ENABLE_CLOUDFLARED=${ENABLE_CLOUDFLARED} \
    NUSHELL_VERSION=${NUSHELL_VERSION} \
    WORKSPACE_DIR=${WORKSPACE_DIR} \
    VENV_DIR=${VENV_DIR} \
    ROCM_VERSION=${ROCM_VERSION} \
    PATH=${VENV_DIR}/bin:/opt/rocm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.title="xforce_AI ROCm base" \
    org.opencontainers.image.description="AMD ROCm development base image for xforce_AI" \
    org.opencontainers.image.vendor="xforce" \
    org.opencontainers.image.version="${XFORCE_IMAGE_VERSION}" \
    org.opencontainers.image.revision="${XFORCE_IMAGE_REVISION}" \
    org.opencontainers.image.source="${XFORCE_IMAGE_SOURCE}" \
    org.opencontainers.image.created="${XFORCE_IMAGE_CREATED}" \
    image.family="xforce-ai" \
    image.variant="rocm" \
    image.release="${XFORCE_IMAGE_VERSION}" \
    image.source="workspace_web/xforce_AI"

COPY docker/common/base-packages.txt /tmp/xforce-base-packages.txt
COPY docker/common/python-requirements.txt /tmp/xforce-python-requirements.txt
COPY docker/common/fastsources.list /tmp/xforce-fastsources.list
COPY docker/common/install-nushell.sh /tmp/xforce-install-nushell.sh
COPY docker/common/nushell/ /tmp/xforce-nushell/
COPY docker/common/provisioner/ /tmp/xforce-provisioner/
COPY docker/common/xforce-provision /tmp/xforce-provision
COPY docker/common/pty_wrapper/ /tmp/xforce-pty-wrapper/
COPY docker/common/xforce-pty-wrap /tmp/xforce-pty-wrap
COPY docker/common/portal/ /tmp/xforce-portal-package/
COPY docker/common/caddy_manager/ /tmp/xforce-caddy-manager/
COPY docker/common/tunnel_manager/ /tmp/xforce-tunnel-manager/
COPY docker/common/caddy/ /tmp/xforce-caddy-config/
COPY docker/common/supervisor/ /tmp/xforce-supervisor/
COPY docker/common/xforce-portal /tmp/xforce-portal
COPY docker/common/xforce-caddy /tmp/xforce-caddy
COPY docker/common/xforce-tunnel /tmp/xforce-tunnel

RUN awk '/BEGIN ubuntu-jammy/{in_block=1; next} /END ubuntu-jammy/{in_block=0} in_block && /^deb /{print}' /tmp/xforce-fastsources.list > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && grep -vE '^\s*(#|$)' /tmp/xforce-base-packages.txt | xargs apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${XFORCE_GID}" "${XFORCE_USER}" \
    && useradd --uid "${XFORCE_UID}" --gid "${XFORCE_GID}" --create-home --shell /bin/bash "${XFORCE_USER}" \
    && mkdir -p /opt/xforce-ai/bin /opt/xforce-ai/lib /opt/xforce-ai/share/workspace-seed /opt/xforce-ai/share/provisioner/examples /opt/portal-aio /etc/xforce-ai/caddy /etc/caddy /etc/xforce_ai_boot.d /etc/supervisor/conf.d "${WORKSPACE_DIR}" "${VENV_DIR}" \
    && python3 -m venv "${VENV_DIR}" \
    && if grep -vE '^\s*(#|$)' /tmp/xforce-python-requirements.txt | grep -q .; then "${VENV_DIR}/bin/pip" install --no-cache-dir --upgrade -r /tmp/xforce-python-requirements.txt; fi \
    && cp -a /tmp/xforce-provisioner /opt/xforce-ai/lib/provisioner \
    && cp -a /tmp/xforce-pty-wrapper /opt/xforce-ai/lib/pty_wrapper \
    && cp -a /tmp/xforce-portal-package /opt/portal-aio/portal \
    && cp -a /tmp/xforce-caddy-manager /opt/portal-aio/caddy_manager \
    && cp -a /tmp/xforce-tunnel-manager /opt/portal-aio/tunnel_manager \
    && cp -a /tmp/xforce-caddy-config/. /etc/xforce-ai/caddy/ \
    && cp /tmp/xforce-supervisor/supervisord.conf /etc/supervisor/supervisord.conf \
    && cp -a /tmp/xforce-supervisor/conf.d/. /etc/supervisor/conf.d/ \
    && cp /tmp/xforce-supervisor/services.yaml /etc/xforce-ai/services.yaml \
    && cp -a /tmp/xforce-provisioner/examples/. /opt/xforce-ai/share/provisioner/examples/ \
    && cp /tmp/xforce-provision /opt/xforce-ai/bin/xforce-provision \
    && cp /tmp/xforce-pty-wrap /opt/xforce-ai/bin/xforce-pty-wrap \
    && cp /tmp/xforce-portal /opt/xforce-ai/bin/xforce-portal \
    && cp /tmp/xforce-caddy /opt/xforce-ai/bin/xforce-caddy \
    && cp /tmp/xforce-tunnel /opt/xforce-ai/bin/xforce-tunnel \
    && chmod 0755 /opt/xforce-ai/bin/xforce-provision /opt/xforce-ai/bin/xforce-pty-wrap /opt/xforce-ai/bin/xforce-portal /opt/xforce-ai/bin/xforce-caddy /opt/xforce-ai/bin/xforce-tunnel \
    && if [ "${ENABLE_NUSHELL}" = "1" ]; then bash /tmp/xforce-install-nushell.sh && { grep -qxF /usr/local/bin/nu /etc/shells || printf '%s\n' /usr/local/bin/nu >> /etc/shells; } && usermod --shell /usr/local/bin/nu "${XFORCE_USER}" && mkdir -p "/home/${XFORCE_USER}/.config/nushell" && cp -a /tmp/xforce-nushell/. "/home/${XFORCE_USER}/.config/nushell/"; fi \
    && chown -R "${XFORCE_UID}:${XFORCE_GID}" "${WORKSPACE_DIR}" "/home/${XFORCE_USER}" "${VENV_DIR}" \
    && rm -rf /tmp/xforce-base-packages.txt /tmp/xforce-python-requirements.txt /tmp/xforce-fastsources.list /tmp/xforce-install-nushell.sh /tmp/xforce-nushell /tmp/xforce-provisioner /tmp/xforce-provision /tmp/xforce-pty-wrapper /tmp/xforce-pty-wrap /tmp/xforce-portal-package /tmp/xforce-caddy-manager /tmp/xforce-tunnel-manager /tmp/xforce-caddy-config /tmp/xforce-supervisor /tmp/xforce-portal /tmp/xforce-caddy /tmp/xforce-tunnel

COPY docker/common/boot/entrypoint.sh /opt/xforce-ai/bin/entrypoint.sh
COPY docker/common/boot/boot_default.sh /opt/xforce-ai/bin/boot_default.sh
COPY docker/common/boot/xforce_ai_boot.d/ /etc/xforce_ai_boot.d/
COPY docker/common/workspace-seed/ /opt/xforce-ai/share/workspace-seed/
COPY docker/common/smoke-test.sh /opt/xforce-ai/bin/smoke-test.sh
COPY docker/common/provisioner-smoke-test.sh /opt/xforce-ai/bin/provisioner-smoke-test.sh
COPY docker/common/pty-wrapper-smoke-test.sh /opt/xforce-ai/bin/pty-wrapper-smoke-test.sh
COPY docker/common/portal-smoke-test.sh /opt/xforce-ai/bin/portal-smoke-test.sh
COPY docker/common/caddy-tunnel-smoke-test.sh /opt/xforce-ai/bin/caddy-tunnel-smoke-test.sh

RUN chmod 0755 /opt/xforce-ai/bin/entrypoint.sh /opt/xforce-ai/bin/boot_default.sh /opt/xforce-ai/bin/smoke-test.sh /opt/xforce-ai/bin/provisioner-smoke-test.sh /opt/xforce-ai/bin/pty-wrapper-smoke-test.sh /opt/xforce-ai/bin/portal-smoke-test.sh /opt/xforce-ai/bin/caddy-tunnel-smoke-test.sh \
    && chmod 0644 /etc/xforce_ai_boot.d/*.sh

WORKDIR ${WORKSPACE_DIR}
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/xforce-ai/bin/entrypoint.sh"]
CMD []
