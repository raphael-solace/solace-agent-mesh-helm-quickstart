FROM ubuntu:24.04

ARG KUBECTL_VERSION=v1.32.2
ARG HELM_VERSION=v3.17.1
ARG MINIKUBE_VERSION=v1.38.0
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    lsof \
    procps \
    && rm -rf /var/lib/apt/lists/*

RUN case "${TARGETARCH}" in \
      amd64|arm64) ARCH="${TARGETARCH}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" \
    && chmod +x /usr/local/bin/kubectl

RUN case "${TARGETARCH}" in \
      amd64|arm64) ARCH="${TARGETARCH}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" \
    | tar -xz -C /tmp \
    && mv "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm \
    && chmod +x /usr/local/bin/helm \
    && rm -rf "/tmp/linux-${ARCH}"

RUN case "${TARGETARCH}" in \
      amd64|arm64) ARCH="${TARGETARCH}" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL -o /usr/local/bin/minikube "https://storage.googleapis.com/minikube/releases/${MINIKUBE_VERSION}/minikube-linux-${ARCH}" \
    && chmod +x /usr/local/bin/minikube

COPY demos/containerized-runner/entrypoint.sh /usr/local/bin/sam-demo-entrypoint
RUN chmod +x /usr/local/bin/sam-demo-entrypoint

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sam-demo-entrypoint"]
