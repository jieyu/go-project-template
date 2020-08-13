# Go project template

This repository is forked from the following project:
https://github.com/thockin/go-build-template

This is a skeleton project for a Go application, which captures the best build techniques I have learned to date.
It uses a Makefile to drive the build (the universal API to software projects) and a Dockerfile to build a docker image.

This has only been tested on Linux, and depends on Docker to build.

## Customizing it

To use this, simply copy these files and make the following changes:

Makefile:
   - replace `cmd/myapp-*` with one directory for each of your binaries.
   - change `DOCKER_REGISTRY_ORG` to the Docker registry you want to use
   - maybe change `SRC_DIRS` if you use some other layout
   - choose a strategy for `VERSION` values - git tags or manual

## Building

Run `make` or `make build` to compile your app.
This will use a Docker image to build your app, with the current directory volume-mounted into place.
This will store incremental state for the fastest possible build.
Run `make all-build` to build for all architectures.

Run `make container` to build the container image.
It will calculate the image tag based on the most recent git tag, and whether the repo is "dirty" since that tag (see `make version`).
Run `make all-container` to build containers for all supported architectures.

Run `make push` to push the container image to `DOCKER_REGISTRY_ORG`.
Run `make all-push` to push the container images for all architectures.

Run `make clean` to clean up.

Run `make help` to get a list of available targets.
