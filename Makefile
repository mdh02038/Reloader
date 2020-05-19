# note: call scripts from /scripts

.PHONY: default build builder-image binary-image test stop clean-images clean push apply deploy release release-all manifest

OS ?= linux
ARCH ?= ??? 
ALL_ARCH ?= arm64 amd64
BUILDER ?= reloader-builder-${ARCH}
BINARY ?= Reloader
DOCKER_IMAGE ?= raquette/reloader
# Default value "dev"
TAG ?= 1.0.0
REPOSITORY_GENERIC = ${DOCKER_IMAGE}:${TAG}
REPOSITORY_ARCH = ${DOCKER_IMAGE}:${TAG}-${ARCH}

VERSION=$(shell cat .version)
BUILD=

GOCMD = go
GOFLAGS ?= $(GOFLAGS:)
LDFLAGS =

default: build test

install:
	"$(GOCMD)" mod download

build:
	"$(GOCMD)" build ${GOFLAGS} ${LDFLAGS} -o "${BINARY}"

builder-image:
	@docker buildx build --platform ${OS}/${ARCH} --network host -t "${BUILDER}" -f build/package/Dockerfile.build .

binary-image: builder-image
	@docker run --network host --rm "${BUILDER}" | docker buildx build --platform ${OS}/${ARCH} --network host -t "${REPOSITORY_ARCH}" -f Dockerfile.run -


release: builder-image binary-image manifest
	@docker push ${REPOSITORY_ARCH}

release-all:
	(set -e ; $(foreach arch,$(ALL_ARCH), \
		make release ARCH=${arch} ; \
	))
	(set -e ; \
                docker manifest push $(REPOSITORY_GENERIC); \
	)

manifest:
	(set -e ; \
		docker manifest create -a $(REPOSITORY_GENERIC) $(REPOSITORY_ARCH); \
		docker manifest annotate --arch $(ARCH) $(REPOSITORY_GENERIC)  $(REPOSITORY_ARCH); \
	)

test:
	"$(GOCMD)" test -timeout 1800s -v ./...

stop:
	@docker stop "${BINARY}"

clean-images: stop
	@docker rmi "${BUILDER}" "${BINARY}"

clean:
	"$(GOCMD)" clean -i

push: ## push the latest Docker image to DockerHub
	docker push $(REPOSITORY)

apply:
	kubectl apply -f deployments/manifests/ -n temp-reloader

deploy: binary-image push applyo

