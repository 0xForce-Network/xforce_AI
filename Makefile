IMAGE_REGISTRY ?= ghcr.io/xforce-ai
IMAGE_NAME ?= xforce-ai
IMAGE_TAG ?= dev
PLATFORMS ?= linux/amd64
PUSH ?= 0

.PHONY: build-cpu build-nvidia build-rocm smoke-cpu check-naming git-status

build-cpu:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) scripts/build-image.sh cpu

build-nvidia:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) scripts/build-image.sh nvidia

build-rocm:
	IMAGE_REGISTRY=$(IMAGE_REGISTRY) IMAGE_NAME=$(IMAGE_NAME) IMAGE_TAG=$(IMAGE_TAG) PLATFORMS=$(PLATFORMS) PUSH=$(PUSH) scripts/build-image.sh rocm

smoke-cpu: build-cpu
	docker run --rm $(IMAGE_REGISTRY)/$(IMAGE_NAME):cpu-$(IMAGE_TAG) /opt/xforce-ai/bin/smoke-test.sh

check-naming:
	! grep -RInE 'va[s]t|va[s]tai|instance[-]tools' docker scripts Makefile .dockerignore

git-status:
	git status --short --branch
