#!/usr/bin/env bash
set -euo pipefail

WORKDIR="${WORKDIR:-/workspace}"
ORIGINAL_KUBECONFIG="${KUBECONFIG:-/root/.kube/config}"
PATCH_LOCAL_KUBECONFIG="${PATCH_LOCAL_KUBECONFIG:-true}"
HOST_HOME="${HOST_HOME:-}"

if [[ -d "${WORKDIR}" ]]; then
  cd "${WORKDIR}"
fi

ensure_kubeconfig() {
  if [[ ! -f "${ORIGINAL_KUBECONFIG}" ]]; then
    return 0
  fi

  if [[ "${PATCH_LOCAL_KUBECONFIG}" != "true" ]]; then
    export KUBECONFIG="${ORIGINAL_KUBECONFIG}"
    return 0
  fi

  local patched
  patched="$(mktemp /tmp/kubeconfig.XXXXXX)"
  cp "${ORIGINAL_KUBECONFIG}" "${patched}"
  export KUBECONFIG="${patched}"

  if [[ -n "${HOST_HOME}" ]]; then
    local escaped_host_home
    escaped_host_home="$(printf '%s\n' "${HOST_HOME}" | sed 's/[.[\*^$()+?{}|\/]/\\&/g')"
    sed -E -i "s#${escaped_host_home}/\\.minikube#/root/.minikube#g" "${KUBECONFIG}"
  fi

  local context cluster server fixed
  while IFS= read -r context; do
    [[ -z "${context}" ]] && continue
    cluster="$(kubectl config --kubeconfig "${KUBECONFIG}" view -o jsonpath="{.contexts[?(@.name==\"${context}\")].context.cluster}" 2>/dev/null || true)"
    [[ -z "${cluster}" ]] && continue
    server="$(kubectl config --kubeconfig "${KUBECONFIG}" view -o jsonpath="{.clusters[?(@.name==\"${cluster}\")].cluster.server}" 2>/dev/null || true)"
    [[ -z "${server}" ]] && continue

    if [[ "${server}" == https://127.0.0.1:* || "${server}" == https://localhost:* ]]; then
      fixed="${server/127.0.0.1/host.docker.internal}"
      fixed="${fixed/localhost/host.docker.internal}"
      kubectl config --kubeconfig "${KUBECONFIG}" set-cluster "${cluster}" --server="${fixed}" >/dev/null
      kubectl config --kubeconfig "${KUBECONFIG}" set-cluster "${cluster}" --insecure-skip-tls-verify=true >/dev/null
      kubectl config --kubeconfig "${KUBECONFIG}" unset "clusters.${cluster}.certificate-authority-data" >/dev/null 2>&1 || true
      kubectl config --kubeconfig "${KUBECONFIG}" unset "clusters.${cluster}.certificate-authority" >/dev/null 2>&1 || true
    fi
  done < <(kubectl config --kubeconfig "${KUBECONFIG}" get-contexts -o name 2>/dev/null || true)
}

normalize_args() {
  if [[ $# -eq 0 ]]; then
    set -- ./demo up
  elif [[ "$1" == "up" || "$1" == "down" ]]; then
    set -- ./demo "$@"
  elif [[ "$1" == "shell" ]]; then
    shift
    set -- bash "$@"
  fi
  printf '%s\0' "$@"
}

ensure_kubeconfig

mapfile -d '' ARGS < <(normalize_args "$@")
exec "${ARGS[@]}"
