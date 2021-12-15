DOCKER_VERSION=20.10.10
COMPOSE_VERSION=2.0.1
COMPOSE_SWITCH_VERSION=1.0.2

alpine: variant = alpine
alpine: build

ubuntu: variant = ubuntu
ubuntu: build

build:
	docker build -t testinfected/dcind-gradle:7-jdk17-$(variant) \
		--build-arg DOCKER_VERSION=${DOCKER_VERSION} \
		--build-arg COMPOSE_VERSION=${COMPOSE_VERSION} \
		--build-arg COMPOSE_SWITCH_VERSION=${COMPOSE_SWITCH_VERSION} \
		$(variant)
