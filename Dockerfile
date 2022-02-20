FROM alpine:3.15

RUN apk add --no-cache \
    ca-certificates=20211220-r0 \
    gawk=5.1.1-r0 \
    git=2.34.1-r0 \
    gnupg=2.2.31-r1 \
    jo=1.4-r0 \
    jq=1.6-r1
    COPY entrypoint.sh /entrypoint.sh
RUN ["chmod", "+x", "/entrypoint.sh"]
# hadolint ignore=DL4006
RUN wget https://github.com/mikefarah/yq/releases/download/v4.20.2/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq
RUN wget -q -O - https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /opt/bin/trivy \
    && export PATH=$PATH:/opt/bin/trivy \
    && trivy filesystem --skip-dirs /opt/bin/trivy --exit-code 1 --no-progress / \
    && trivy image --reset \
    && rm -rf /opt/bin/trivy \
    && rm -rf /root/.cache

ENTRYPOINT ["/entrypoint.sh"]
