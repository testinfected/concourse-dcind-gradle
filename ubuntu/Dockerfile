FROM gradle:7-jdk17

ARG DOCKER_VERSION=20.10.10
ENV DOCKER_URL="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"

ARG COMPOSE_VERSION=2.0.1
ENV COMPOSE_URL="https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-x86_64"

ARG COMPOSE_SWITCH_VERSION=1.0.2
ENV COMPOSE_SWITCH_URL="https://github.com/docker/compose-switch/releases/download/v${COMPOSE_SWITCH_VERSION}/docker-compose-linux-amd64"

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get -y install \
        bash \
        curl \
        iptables \
        util-linux \
        ca-certificates \
        net-tools \
        iproute2 \
        && \
    apt-get clean && \

    # Install Docker from binaries
    curl -fL ${DOCKER_URL} | tar zx -C /bin --strip-components 1 && \
    chmod +x /bin/docker* && \

    # Install Compose V2
    mkdir -p /usr/local/lib/docker/cli-plugins && \
    curl -SL ${COMPOSE_URL} -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \

    # Install Compose Switch
    curl -fL ${COMPOSE_SWITCH_URL} -o /usr/local/bin/compose-switch && \
    chmod +x /usr/local/bin/compose-switch && \
    update-alternatives --install /usr/local/bin/docker-compose docker-compose /usr/local/bin/compose-switch 99

COPY docker-lib.sh /docker-lib.sh
COPY entrypoint.sh /bin/entrypoint.sh

ENTRYPOINT ["entrypoint.sh"]
