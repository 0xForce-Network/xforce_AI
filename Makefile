IMAGE_REGISTRY ?= ghcr.io/xforce-ai
IMAGE_NAME ?= xforce-ai
IMAGE_TAG ?= dev
PLATFORMS ?= linux/amd64
PUSH ?= 0
VARIANTS ?= cpu,nvidia,rocm
ENABLE_NUSHELL ?= 1
ENABLE_CLOUDFLARED ?= 0

.PHONY: build-cpu build-nvidia build-rocm smoke-cpu check-naming git-status preflight smoke-local build-all release-dry-run print-tags hil-validate hil-smoke scheduler-smoke

build-cpu:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) ENABLE_NUSHELL=$(ENABLE_NUSHELL) ENABLE_CLOUDFLARED=$(ENABLE_CLOUDFLARED) scripts/build-image.sh cpu

build-nvidia:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) ENABLE_NUSHELL=$(ENABLE_NUSHELL) ENABLE_CLOUDFLARED=$(ENABLE_CLOUDFLARED) scripts/build-image.sh nvidia

build-rocm:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) ENABLE_NUSHELL=$(ENABLE_NUSHELL) ENABLE_CLOUDFLARED=$(ENABLE_CLOUDFLARED) scripts/build-image.sh rocm

smoke-cpu: build-cpu
	docker run --rm $(IMAGE_REGISTRY)/$(IMAGE_NAME):cpu-$(IMAGE_TAG) /opt/xforce-ai/bin/smoke-test.sh

check-naming:
	! grep -RInE 'va[s]t|va[s]tai|instance[-]tools' docker scripts Makefile .dockerignore

preflight:
	scripts/ci-smoke.sh preflight

smoke-local:
	ENABLE_NUSHELL=0 ENABLE_CLOUDFLARED=0 IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=linux/amd64 PUSH=0 LOAD=1 scripts/ci-smoke.sh smoke

build-all:
	@IFS=','; for variant in $(VARIANTS); do \
		IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) ENABLE_NUSHELL=$(ENABLE_NUSHELL) ENABLE_CLOUDFLARED=$(ENABLE_CLOUDFLARED) scripts/build-image.sh $$variant; \
	done

release-dry-run:
	@IFS=','; for variant in $(VARIANTS); do \
		echo "## $$variant"; \
		OUTPUT=lines scripts/image-tags.sh $$variant $(IMAGE_TAG); \
		IMAGE_TAGS="$$(OUTPUT=csv scripts/image-tags.sh $$variant $(IMAGE_TAG))" DRY_RUN=1 PUSH=0 PLATFORMS=$(PLATFORMS) scripts/build-image.sh $$variant; \
	done

print-tags:
	@IFS=','; for variant in $(VARIANTS); do OUTPUT=lines scripts/image-tags.sh $$variant $(IMAGE_TAG); done

hil-validate:
	python3 -m hil_orchestrator validate-config --models configs/hil/model-requirements.yaml --suites configs/hil/hil-suites.yaml --inventory configs/hil/fixture-gpu-inventory.yaml

hil-smoke:
	bash scripts/hil-fixture-smoke.sh

scheduler-smoke:
	bash scripts/model-scheduler-fixture-smoke.sh

git-status:
	git status --short --branch
