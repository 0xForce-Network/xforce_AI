ARG CUDA_VERSION=12.4.1
ARG UBUNTU_VERSION=22.04
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${UBUNTU_VERSION}

ARG PYTHON_VERSION=3.12
ARG TARGETARCH
ARG XFORCE_USER=user
ARG XFORCE_UID=1000
ARG XFORCE_GID=1000
ARG WORKSPACE_DIR=/workspace
ARG VENV_DIR=/venv/main
ARG ENABLE_NUSHELL=1
ARG ENABLE_PORTAL=1
ARG XFORCE_IMAGE_VERSION=dev
ARG NUSHELL_VERSION=0.113.1
ARG NUSHELL_SHA256_AMD64=9008d309aaa35e29ed5d5985306a83e2bf5093e31677d4cd969914552d12b8fb
ARG NUSHELL_SHA256_ARM64=08b94c6fd9c66881616df4c89adc03e8a42a57fdf6876cfd1b16cec7e82348b4
ARG CUDA_VERSION=12.4.1

ENV DEBIAN_FRONTEND=noninteractive \
    XFORCE_IMAGE_VARIANT=nvidia \
    XFORCE_IMAGE_VERSION=${XFORCE_IMAGE_VERSION} \
    XFORCE_USER=${XFORCE_USER} \
    ENABLE_NUSHELL=${ENABLE_NUSHELL} \
    NUSHELL_VERSION=${NUSHELL_VERSION} \
    WORKSPACE_DIR=${WORKSPACE_DIR} \
    VENV_DIR=${VENV_DIR} \
    CUDA_VERSION=${CUDA_VERSION} \
    PATH=${VENV_DIR}/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

LABEL org.opencontainers.image.title="xforce_AI NVIDIA CUDA base" \
    org.opencontainers.image.description="NVIDIA CUDA development base image for xforce_AI" \
    org.opencontainers.image.vendor="xforce" \
    org.opencontainers.image.version="${XFORCE_IMAGE_VERSION}"

COPY docker/common/base-packages.txt /tmp/xforce-base-packages.txt
COPY docker/common/python-requirements.txt /tmp/xforce-python-requirements.txt
COPY docker/common/fastsources.list /tmp/xforce-fastsources.list
COPY docker/common/install-nushell.sh /tmp/xforce-install-nushell.sh
COPY docker/common/nushell/ /tmp/xforce-nushell/

RUN awk '/BEGIN ubuntu-jammy/{in_block=1; next} /END ubuntu-jammy/{in_block=0} in_block && /^deb /{print}' /tmp/xforce-fastsources.list > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/ubuntu.sources \
    && apt-get update \
    && grep -vE '^\s*(#|$)' /tmp/xforce-base-packages.txt | xargs apt-get install -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid "${XFORCE_GID}" "${XFORCE_USER}" \
    && useradd --uid "${XFORCE_UID}" --gid "${XFORCE_GID}" --create-home --shell /bin/bash "${XFORCE_USER}" \
    && mkdir -p /opt/xforce-ai/bin /opt/xforce-ai/lib /opt/xforce-ai/share/workspace-seed /opt/portal-aio /etc/xforce_ai_boot.d /etc/supervisor/conf.d "${WORKSPACE_DIR}" "${VENV_DIR}" \
    && python3 -m venv "${VENV_DIR}" \
    && if grep -vE '^\s*(#|$)' /tmp/xforce-python-requirements.txt | grep -q .; then "${VENV_DIR}/bin/pip" install --no-cache-dir --upgrade -r /tmp/xforce-python-requirements.txt; fi \
    && if [ "${ENABLE_NUSHELL}" = "1" ]; then bash /tmp/xforce-install-nushell.sh && { grep -qxF /usr/local/bin/nu /etc/shells || printf '%s\n' /usr/local/bin/nu >> /etc/shells; } && usermod --shell /usr/local/bin/nu "${XFORCE_USER}" && mkdir -p "/home/${XFORCE_USER}/.config/nushell" && cp -a /tmp/xforce-nushell/. "/home/${XFORCE_USER}/.config/nushell/"; fi \
    && chown -R "${XFORCE_UID}:${XFORCE_GID}" "${WORKSPACE_DIR}" "/home/${XFORCE_USER}" "${VENV_DIR}" \
    && rm -rf /tmp/xforce-base-packages.txt /tmp/xforce-python-requirements.txt /tmp/xforce-fastsources.list /tmp/xforce-install-nushell.sh /tmp/xforce-nushell

COPY docker/common/boot/entrypoint.sh /opt/xforce-ai/bin/entrypoint.sh
COPY docker/common/boot/boot_default.sh /opt/xforce-ai/bin/boot_default.sh
COPY docker/common/boot/xforce_ai_boot.d/ /etc/xforce_ai_boot.d/
COPY docker/common/workspace-seed/ /opt/xforce-ai/share/workspace-seed/
COPY docker/common/smoke-test.sh /opt/xforce-ai/bin/smoke-test.sh

RUN chmod 0755 /opt/xforce-ai/bin/entrypoint.sh /opt/xforce-ai/bin/boot_default.sh /opt/xforce-ai/bin/smoke-test.sh \
    && chmod 0644 /etc/xforce_ai_boot.d/*.sh

WORKDIR ${WORKSPACE_DIR}
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/xforce-ai/bin/entrypoint.sh"]
CMD []
