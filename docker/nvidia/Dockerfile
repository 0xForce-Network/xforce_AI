ARG CUDA_VERSION=12.8.1
ARG UBUNTU_VERSION=24.04
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}

ARG UBUNTU_VERSION=24.04
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
ARG ENABLE_FASTSOURCES=0
ARG XFORCE_IMAGE_VERSION=dev
ARG XFORCE_IMAGE_REVISION=unknown
ARG XFORCE_IMAGE_SOURCE=https://github.com/xforce-ai/xforce-ai
ARG XFORCE_IMAGE_CREATED=unknown
ARG NUSHELL_VERSION=0.113.1
ARG NUSHELL_SHA256_AMD64=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb
ARG NUSHELL_SHA256_ARM64=08b94c6fd9c66881616df4c89adc03e8a42a57fdf6876cfd1b16cec7e82348b4
ARG CADDY_VERSION=2.11.4
ARG CADDY_SHA512_AMD64=8220d1f013b6f27510247b2360c9e0ca9f018feebd82515f07635318b34ff9777ccc8fd0b6e6f2486ce3a33fe389fbb7db12d05baa474f4587509fb4f5ebf1c9
ARG CADDY_SHA512_ARM64=d5a7c423853c24a799765e0e8210d5c7c22a8f56ed37a3cae2fb9f58be138853c02b4efd6b59d576e6d8c7c0d30b9c1592deeaa6a536ff69bcca23b8c1ea709c
ARG CLOUDFLARED_VERSION=2025.6.0
ARG CLOUDFLARED_SHA256_AMD64=
ARG CLOUDFLARED_SHA256_ARM64=
ARG CUDA_VERSION=12.8.1

ENV DEBIAN_FRONTEND=noninteractive \
    XFORCE_IMAGE_VARIANT=nvidia \
    XFORCE_IMAGE_VERSION=${XFORCE_IMAGE_VERSION} \
    XFORCE_USER=${XFORCE_USER} \
    ENABLE_NUSHELL=${ENABLE_NUSHELL} \
    ENABLE_CLOUDFLARED=${ENABLE_CLOUDFLARED} \
    ENABLE_FASTSOURCES=${ENABLE_FASTSOURCES} \
    NUSHELL_VERSION=${NUSHELL_VERSION} \
    CADDY_VERSION=${CADDY_VERSION} \
    WORKSPACE_DIR=${WORKSPACE_DIR} \
    VENV_DIR=${VENV_DIR} \
    CUDA_VERSION=${CUDA_VERSION} \
    PATH=${VENV_DIR}/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.title="xforce_AI NVIDIA CUDA base" \
    org.opencontainers.image.description="NVIDIA CUDA development base image for xforce_AI" \
    org.opencontainers.image.vendor="xforce" \
    org.opencontainers.image.version="${XFORCE_IMAGE_VERSION}" \
    org.opencontainers.image.revision="${XFORCE_IMAGE_REVISION}" \
    org.opencontainers.image.source="${XFORCE_IMAGE_SOURCE}" \
    org.opencontainers.image.created="${XFORCE_IMAGE_CREATED}" \
    image.family="xforce-ai" \
    image.variant="nvidia" \
    image.release="${XFORCE_IMAGE_VERSION}" \
    image.source="workspace_web/xforce_AI"

COPY docker/common/base-packages.txt /tmp/xforce-base-packages.txt
COPY docker/common/python-requirements.txt /tmp/xforce-python-requirements.txt
COPY docker/common/fastsources.list /tmp/xforce-fastsources.list
COPY docker/common/install-nushell.sh /tmp/xforce-install-nushell.sh
COPY docker/common/install-caddy.sh /tmp/xforce-install-caddy.sh
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

RUN apt_opts='-o Acquire::Retries=5 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::ForceIPv4=true' \
    && if [ "${ENABLE_FASTSOURCES}" = "1" ]; then \
    case "${UBUNTU_VERSION}" in \
    22.04) ubuntu_suite=jammy ;; \
    24.04) ubuntu_suite=noble ;; \
    *) echo "unsupported Ubuntu version: ${UBUNTU_VERSION}" >&2; exit 2 ;; \
    esac \
    && awk "/BEGIN ubuntu-${ubuntu_suite}/{in_block=1; next} /END ubuntu-${ubuntu_suite}/{in_block=0} in_block && /^deb /{print}" /tmp/xforce-fastsources.list > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/ubuntu.sources; \
    fi \
    && apt-get ${apt_opts} update \
    && grep -vE '^\s*(#|$)' /tmp/xforce-base-packages.txt | xargs apt-get ${apt_opts} install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && xforce_group="$(getent group "${XFORCE_GID}" | cut -d: -f1 || true)" \
    && if [ -z "${xforce_group}" ]; then groupadd --gid "${XFORCE_GID}" "${XFORCE_USER}"; elif [ "${xforce_group}" != "${XFORCE_USER}" ]; then groupmod --new-name "${XFORCE_USER}" "${xforce_group}"; fi \
    && xforce_user="$(getent passwd "${XFORCE_UID}" | cut -d: -f1 || true)" \
    && if [ -z "${xforce_user}" ]; then useradd --uid "${XFORCE_UID}" --gid "${XFORCE_USER}" --create-home --home-dir "/home/${XFORCE_USER}" --shell /bin/bash "${XFORCE_USER}"; elif [ "${xforce_user}" != "${XFORCE_USER}" ]; then usermod --login "${XFORCE_USER}" --home "/home/${XFORCE_USER}" --move-home --shell /bin/bash "${xforce_user}"; else usermod --home "/home/${XFORCE_USER}" --move-home --shell /bin/bash "${XFORCE_USER}"; fi \
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
    && CADDY_VERSION="${CADDY_VERSION}" CADDY_SHA512_AMD64="${CADDY_SHA512_AMD64}" CADDY_SHA512_ARM64="${CADDY_SHA512_ARM64}" bash /tmp/xforce-install-caddy.sh \
    && if [ "${ENABLE_NUSHELL}" = "1" ]; then bash /tmp/xforce-install-nushell.sh && { grep -qxF /usr/local/bin/nu /etc/shells || printf '%s\n' /usr/local/bin/nu >> /etc/shells; } && usermod --shell /usr/local/bin/nu "${XFORCE_USER}" && mkdir -p "/home/${XFORCE_USER}/.config/nushell" && cp -a /tmp/xforce-nushell/. "/home/${XFORCE_USER}/.config/nushell/"; fi \
    && chown -R "${XFORCE_UID}:${XFORCE_GID}" "${WORKSPACE_DIR}" "/home/${XFORCE_USER}" "${VENV_DIR}" \
    && rm -rf /tmp/xforce-base-packages.txt /tmp/xforce-python-requirements.txt /tmp/xforce-fastsources.list /tmp/xforce-install-nushell.sh /tmp/xforce-install-caddy.sh /tmp/xforce-nushell /tmp/xforce-provisioner /tmp/xforce-provision /tmp/xforce-pty-wrapper /tmp/xforce-pty-wrap /tmp/xforce-portal-package /tmp/xforce-caddy-manager /tmp/xforce-tunnel-manager /tmp/xforce-caddy-config /tmp/xforce-supervisor /tmp/xforce-portal /tmp/xforce-caddy /tmp/xforce-tunnel

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
