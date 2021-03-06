# concourse-dcind-gradle
Docker in Docker containers on the JVM. Optimized for use with [Concourse CI](http://concourse.ci/).

The images are Alpine or Ubuntu based. They include Docker, Docker Compose, Docker Compose Switch, and Gradle as well as Bash.

Images published to Docker Hub: [testinfected/dcind-gradle](https://hub.docker.com/repository/docker/testinfected/dcind-gradle).

Inspired by [karlkfi/concourse-dcind](https://github.com/karlkfi/concourse-dcind/).

## Features

Like karlkfi/concourse-dcind, these images:

- Do not require the user to manually start docker.
- Use errexit, pipefail, and nounset.
- Configure timeout (`DOCKERD_TIMEOUT`) on dockerd start to account for mis-configuration (docker log will be output).
- Accept arbitrary dockerd arguments via optional `DOCKER_OPTS` environment variable.
- Pass through `--garden-mtu` from the parent Gardian container if `--mtu` is not specified in `DOCKER_OPTS`.
- Set `--data-root /scratch/docker` to bypass the graph filesystem if `--data-root` is not specified in `DOCKER_OPTS`.

On top of karlkfi/concourse-dcind, these images:

- Include Gradle for projects on the JVM
- Preload all Concourse images in OCI format that are inputs to the Job

## Build

```
make alpine
```

... or ....

```
make ubuntu
```

## Example

Here is an example of a Concourse [job](http://concourse.ci/concepts.html) that uses ```testinfects/dcind-gradle``` image that spawns a Selenium image using Docker Compose, and then runs the integration test suite. You can find a full version of this example in the [```bee-software/kickstart```](https://github.com/bee-software/kickstart/blob/master/ci/pipeline.yml) repository.

```yaml
---
resources:
  - name: code
    type: git
    icon: github
    source:
      uri: https://github.com/bee-software/kickstart.git
      branch: master

  - name: selenium-chrome
    type: registry-image
    icon: docker
    source:
      repository: selenium/standalone-chrome
#      tag: 96.0


jobs:
  - name: acceptance
    plan:
      - in_parallel:
        - get: code
          params:
            depth: 1
          passed: [test]
          trigger: true
        # Get Selenium image in OCI format
        - get: selenium-chrome
          params: {format: oci}
      - task: acceptance-tests
        privileged: true
        platform: linux

        image_resource:
          type: registry-image
          source:
            repository: testinfected/dcind-gradle
            tag: 7-jdk17-alpine

        # Cache the Gradle repository directory
        caches:
          - path: $HOME/.gradle
        inputs:
          - name: code
          - name: selenium-chrome
        run:
          path: entrypoint.sh
          args:
            - bash
            - -ceux
            - |
              cd code
              
              cat > compose.acceptance.yaml <<EOF
              version: '3'

              services:
                selenium:
                  image: selenium/standalone-chrome
                  shm_size: 2gb
                  extra_hosts:
                    - "host.docker.internal:host-gateway"
                  ports:
                    - "4444:4444"
              EOF
              
              # Start Selenium Chrome Docker image using Compose V2               
              docker compose -f compose.acceptance.yml up -d

              # Get the container IP adress for running the acceptance tests
              SERVER_HOST=$(/sbin/ifconfig docker0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}') \
              gradle acceptanceTest
```
