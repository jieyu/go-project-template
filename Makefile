GITHUB_ORG ?= jieyu
GITHUB_REPO ?= go-project-template

DOCKER_REGISTRY ?= jieyu

# Platforms to build the binaries for.
ALL_PLATFORMS := linux/amd64 linux/arm64

# Non public Go modules
# E.g., GOPRIVATE=*.corp.example.com,rsc.io/private
GOPRIVATE ?=

#####################################################################
# The following variables should not require tweaking.
#####################################################################

SHELL := /bin/bash -euo pipefail

ROOT_DIR := $(shell git rev-parse --show-toplevel)
SRC_DIRS := cmd pkg # directories which hold app source (not vendored)

# The binaries to build (just the basenames).
BINS := $(shell ls cmd/)

# Golang related.
GOOS ?= $(shell go env GOOS)
GOARCH ?= $(shell go env GOARCH)
GO_DEV_DIR := .go
GOPATH_DIR := $(GO_DEV_DIR)/gopath
GOCACHE_DIR := $(GO_DEV_DIR)/cache

# Git related.
GIT_COMMIT := $(shell git rev-parse "HEAD^{commit}")
GIT_VERSION := $(shell git describe --tags --always --dirty)

TAG := $(GIT_VERSION)__$(GOOS)_$(GOARCH)

# Docker related.
BASE_IMAGE ?= alpine:3
BUILD_IMAGE ?= golang:1.14-buster

# Other constants.

#####################################################################
# Build rules.
#####################################################################

export GO111MODULE := on
export GOPRIVATE

.DEFAULT_GOAL := all

# Directories that we need created to build/test.
BUILD_DIRS :=            \
  bin/$(GOOS)_$(GOARCH)  \
  $(GOPATH_DIR)          \
  $(GOCACHE_DIR)         \
  .docker

# All the output binaries.
OUTBINS := $(foreach bin,$(BINS),bin/$(GOOS)_$(GOARCH)/$(bin))

# If you want to build all binaries, see the 'all-build' rule.
# If you want to build all containers, see the 'all-container' rule.
# If you want to build AND push all containers, see the 'all-push' rule.
all: # @HELP builds binaries for one platform ($GOOS/$GOARCH)
all: build

# For the following OS/ARCH expansions, we transform OS/ARCH into OS_ARCH
# because make pattern rules don't match with embedded '/' characters.
build-%:
	@$(MAKE) build                        \
	    --no-print-directory              \
	    GOOS=$(firstword $(subst _, ,$*)) \
	    GOARCH=$(lastword $(subst _, ,$*))

container-%:
	@$(MAKE) container                    \
	    --no-print-directory              \
	    GOOS=$(firstword $(subst _, ,$*)) \
	    GOARCH=$(lastword $(subst _, ,$*))

push-%:
	@$(MAKE) push                         \
	    --no-print-directory              \
	    GOOS=$(firstword $(subst _, ,$*)) \
	    GOARCH=$(lastword $(subst _, ,$*))

all-build: # @HELP builds binaries for all platforms
all-build: $(addprefix build-, $(subst /,_, $(ALL_PLATFORMS)))

all-container: # @HELP builds containers for all platforms
all-container: $(addprefix container-, $(subst /,_, $(ALL_PLATFORMS)))

all-push: # @HELP pushes containers for all platforms to the defined registry
all-push: $(addprefix push-, $(subst /,_, $(ALL_PLATFORMS)))

.PHONY: build
build:
	@docker run                            \
	    -i                                 \
	    --rm                               \
	    -u $$(id -u):$$(id -g)             \
	    -v $$(pwd):/src                    \
	    -w /src                            \
	    -v $$(pwd)/$(GOCACHE_DIR):/.cache  \
	    $(BUILD_IMAGE)                     \
	    /bin/sh -c "                       \
	        make host.build                \
	        GOARCH="$(GOARCH)"             \
		GOOS="$(GOOS)"                 \
	    "

host.build: $(OUTBINS)

# We use PHONY here so that go build is always triggered. If nothing
# has changed, no extra work would be done by the golang tool chain.
.PHONY: $(OUTBINS)
$(OUTBINS): $(BUILD_DIRS)
	@                                                                   \
	GOARCH="$(GOARCH)"                                                  \
	GOOS="$(GOOS)"                                                      \
	GOROOT_FINAL="/go"                                                  \
	GOPATH="$$(pwd)/$(GOPATH_DIR)"                                      \
	GOCACHE="$$(pwd)/$(GOCACHE_DIR)"                                    \
	CGO_ENABLED=0                                                       \
	go build                                                            \
	    -v -o $@                                                        \
	    -installsuffix "static"                                         \
	    -ldflags "-X $(go list -m)/pkg/version.Version=$(GIT_VERSION)"  \
	    ./cmd/$(@F)

# Example: make shell CMD="-c 'date > datefile'"
shell: # @HELP launches a shell in the containerized build environment
shell: $(BUILD_DIRS)
	@echo "launching a shell in the containerized build environment"
	@docker run                                                 \
	    -ti                                                     \
	    --rm                                                    \
	    -u $$(id -u):$$(id -g)                                  \
	    -v $$(pwd):/src                                         \
	    -w /src                                                 \
	    -v $$(pwd)/bin/$(GOOS)_$(GOARCH):/go/bin                \
	    -v $$(pwd)/bin/$(GOOS)_$(GOARCH):/go/bin/$(OS)_$(ARCH)  \
	    -v $$(pwd)/$(GOCACHE_DIR):/.cache                       \
	    --env HTTP_PROXY=$(HTTP_PROXY)                          \
	    --env HTTPS_PROXY=$(HTTPS_PROXY)                        \
	    $(BUILD_IMAGE)                                          \
	    /bin/sh $(CMD)

CONTAINER_DOTFILES = $(foreach bin,$(BINS),.docker/container-$(subst /,_,$(DOCKER_REGISTRY)/$(bin))-$(TAG))

container: # @HELP builds containers for one platform ($GOOS/$GOARCH)
container: $(CONTAINER_DOTFILES)
	@for bin in $(BINS); do                                 \
	    echo "container: $(DOCKER_REGISTRY)/$$bin:$(TAG)";  \
	done

# Each container-dotfile target can reference a $(BIN) variable.
# This is done in 2 steps to enable target-specific variables.
$(foreach bin,$(BINS),$(eval $(strip                                           \
.docker/container-$(subst /,_,$(DOCKER_REGISTRY)/$(bin))-$(TAG): BIN = $(bin)  \
)))
$(foreach bin,$(BINS),$(eval                                                                              \
.docker/container-$(subst /,_,$(DOCKER_REGISTRY)/$(bin))-$(TAG): bin/$(GOOS)_$(GOARCH)/$(bin) Dockerfile  \
))

# This is the target definition for all container-dotfiles.
# These are used to track build state in hidden files.
$(CONTAINER_DOTFILES): $(BUILD_DIRS)
ifeq ($(GOOS),darwin)
	$(error "Cannot make container on $(GOOS). Please use 'make container GOOS=linux'")
endif
	@docker build                                  \
	    --build-arg BASE_IMAGE=$(BASE_IMAGE)       \
	    --build-arg ARCH=$(GOARCH)                 \
	    --build-arg OS=$(GOOS)                     \
	    --build-arg BIN=$(BIN)                     \
	    -t $(DOCKER_REGISTRY)/$(BIN):$(TAG) .
	@docker images -q $(DOCKER_REGISTRY)/$(BIN):$(TAG) > $@
	@echo

push: # @HELP pushes the container for one platform ($GOOS/$GOARCH) to the defined registry
push: $(CONTAINER_DOTFILES)
	@for bin in $(BINS); do                           \
	    docker push $(DOCKER_REGISTRY)/$$bin:$(TAG);  \
	done

manifest-list: # @HELP builds a manifest list of containers for all platforms
manifest-list: all-push
	@for bin in $(BINS); do                                              \
	    platforms=$$(echo $(ALL_PLATFORMS) | sed 's/ /,/g');             \
	    manifest-tool                                                    \
	        --username=oauth2accesstoken                                 \
	        --password=$$(gcloud auth print-access-token)                \
	        push from-args                                               \
	        --platforms "$$platforms"                                    \
	        --template $(DOCKER_REGISTRY)/$$bin:$(GIT_VERSION)__OS_ARCH  \
	        --target $(DOCKER_REGISTRY)/$$bin:$(GIT_VERSION)

version: # @HELP outputs the version string
version:
	@echo $(GIT_VERSION)

test: # @HELP runs tests, as defined in ./build/test.sh
test: $(BUILD_DIRS)
	@docker run                            \
	    -i                                 \
	    --rm                               \
	    -u $$(id -u):$$(id -g)             \
	    -v $$(pwd):/src                    \
	    -w /src                            \
	    -v $$(pwd)/$(GOCACHE_DIR):/.cache  \
	    $(BUILD_IMAGE)                     \
	    /bin/sh -c "                       \
	        make host.test                 \
	    "

host.test: $(BUILD_DIRS)
	@                                           \
	GOPATH="$$(pwd)/$(GOPATH_DIR)"              \
	GOCACHE="$$(pwd)/$(GOCACHE_DIR)"            \
	CGO_ENABLED=0                               \
	go test -v                                  \
	     -coverprofile $(GO_DEV_DIR)/cover.out  \
	     -installsuffix "static"                \
	     $(SRC_DIRS:%=./%/...)

$(BUILD_DIRS):
	@mkdir -p $@

cover:
	@go tool cover -html=$(GO_DEV_DIR)/cover.out

clean: # @HELP removes built binaries and temporary files
clean: clean.container clean.go-modcache clean.bin

clean.container:
	@rm -rf .docker

clean.go-modcache:
	@                               \
	GOPATH="$$(pwd)/$(GOPATH_DIR)"  \
	go clean -modcache

clean.bin:
	@rm -rf $(GO_DEV_DIR) bin

help: # @HELP prints this message
help:
	@echo "VARIABLES:"
	@echo "  BINS = $(BINS)"
	@echo "  GOOS = $(GOOS)"
	@echo "  GOARCH = $(GOARCH)"
	@echo "  DOCKER_REGISTRY = $(DOCKER_REGISTRY)"
	@echo
	@echo "TARGETS:"
	@grep -hE '^.*: *# *@HELP' $(MAKEFILE_LIST) | sort  \
	    | awk '                                         \
	        BEGIN {FS = ": *# *@HELP"};                 \
	        { printf "  %-30s %s\n", $$1, $$2 };        \
	    '
