#!/bin/bash
set -e

# Check if required parameters are provided
if [ $# -lt 2 ]; then
  echo "Usage: $0 <namespace> <expected_replicas> [timeout]"
  exit 1
fi

NAMESPACE="$1"
REPLICAS="$2"
TIMEOUT="${3:-30}"  # Default timeout: 30 attempts

log_info() {
  echo "ℹ️  $1"
}

log_error() {
  echo "::error::$1" >&2
  exit 1
}

log_info "Waiting for Vault pods to be ready in namespace '$NAMESPACE'..."

for i in $(seq 1 $TIMEOUT); do
  RUNNING_PODS=$(oc get pods -l app.kubernetes.io/name=vault -n $NAMESPACE -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w | tr -d ' ')
  TOTAL_PODS=$(oc get pods -l app.kubernetes.io/name=vault -n $NAMESPACE --no-headers 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  
  log_info "Running pods: $RUNNING_PODS/$TOTAL_PODS (Expected: $REPLICAS)"
  
  if [ "$RUNNING_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -ge "$REPLICAS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
    log_info "All $TOTAL_PODS Vault pods are running."
    
    # Additional check for container readiness
    READY_PODS=$(oc get pods -l app.kubernetes.io/name=vault -n $NAMESPACE -o jsonpath='{.items[?(@.status.containerStatuses[0].ready==true)].metadata.name}' | wc -w | tr -d ' ')
    if [ "$READY_PODS" -ge "$REPLICAS" ]; then
      log_info "All Vault pods are ready."
      exit 0
    fi
  fi
  
  if [ $i -eq $TIMEOUT ]; then
    log_error "Timed out waiting for Vault pods to be ready. Current pod status:"
    oc get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o wide
    exit 1
  fi
  
  sleep 10
done

exit 1
