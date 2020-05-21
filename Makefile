# note: call scripts from /scripts

.PHONY: default build builder-image binary-image test stop clean-images clean push apply deploy release release-all manifest push clean-image

OS ?= linux
ARCH ?= ??? 
ALL_ARCH ?= arm64 amd64
BUILDER ?= reloader-builder-${ARCH}
BINARY ?= Reloader
DOCKER_IMAGE ?= raquette/reloader
# Default value "dev"
TAG ?= v0.0.58.0
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
	docker buildx build --platform ${OS}/${ARCH} --build-arg GOARCH=$(ARCH) --network host -t "${BUILDER}" -f build/package/Dockerfile.build .

reloader-${ARCH}.tar:
	docker buildx build --platform ${OS}/${ARCH} --build-arg GOARCH=$(ARCH) --network host -t "${BUILDER}" -f build/package/Dockerfile.build .
	docker run --network host --rm "${BUILDER}" > reloader-${ARCH}.tar

binary-image: reloader-${ARCH}.tar
	cat reloader-${ARCH}.tar | docker buildx build --platform ${OS}/${ARCH} -t "${REPOSITORY_ARCH}"  -f Dockerfile.run -

push:
	docker push ${REPOSITORY_ARCH}

#release: builder-image binary-image push manifest
release:  binary-image push manifest

release-all:
	-rm -rf ~/.docker/manifests/*
	(set -e ; $(foreach arch,$(ALL_ARCH), \
		make release ARCH=${arch} ; \
	))
	(set -e ; \
                docker manifest push --purge $(REPOSITORY_GENERIC); \
	)

manifest:
	(set -e ; \
		docker manifest create -a $(REPOSITORY_GENERIC) $(REPOSITORY_ARCH); \
		docker manifest annotate --arch $(ARCH) $(REPOSITORY_GENERIC)  $(REPOSITORY_ARCH); \
	)

test:
	"$(GOCMD)" test -timeout 1800s -v ./...

stop:
	-docker stop "${BINARY}"

clean-images: stop
	-docker rmi "${BINARY}"
	(set -e ; $(foreach arch,$(ALL_ARCH), \
	    make clean-image ARCH=${arch};  \
	))
	-docker rmi "${REPOSITORY_GENERIC}"

clean-image: 
	-docker rmi "${BUILDER}" 
	-docker rmi "${REPOSITORY_ARCH}" 
	-rm -rf ~/.docker/manifests/*

clean:
	-"$(GOCMD)" clean -i
	-rm -rf reloader-*.tar


apply:
	kubectl apply -f deployments/manifests/ -n temp-reloader

deploy: binary-image push applyo

