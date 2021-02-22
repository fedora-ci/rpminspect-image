FROM registry.fedoraproject.org/fedora:33
LABEL maintainer "Fedora-CI"
LABEL description="rpminspect for fedora-ci"

ENV RPMINSPECT_VERSION=1.3-0.1.202102181923git.fc33
ENV RPMINSPECT_DATA_VERSION=1:1.4-0.1.202101222127git.fc33

ENV RPMINSPECT_WORKDIR=/workdir/
ENV HOME=${RPMINSPECT_WORKDIR}

RUN mkdir -p ${RPMINSPECT_WORKDIR} &&\
    chmod 777 ${RPMINSPECT_WORKDIR}

RUN dnf -y install 'dnf-command(copr)' && \
    dnf -y copr enable dcantrell/rpminspect

RUN dnf -y install \
    rpminspect-${RPMINSPECT_VERSION} \
    rpminspect-data-fedora-${RPMINSPECT_DATA_VERSION} \
    libabigail \
    koji \
    xmlrpc-c-apps \
    && dnf clean all

COPY rpminspect_runner.sh /usr/local/bin/

WORKDIR ${RPMINSPECT_WORKDIR}
