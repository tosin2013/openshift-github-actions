#!/bin/bash
set -e

# Check if required parameters are provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 <namespace> [timeout]"
  exit 1
fi

NAMESPACE="$1"
TIMEOUT="${2:-60}"  # Default timeout: 60 seconds
START_TIME=$(date +%s)

log_info() {
  echo "ℹ️  $1"
}

log_warning() {
  echo "⚠️  $1"
}

log_error() {
  echo "::error::$1" >&2
}

# Function to get Vault status
get_vault_status() {
  local pod=$1
  local namespace=$2
  
  oc exec -n "$namespace" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null || echo "{}"
}

log_info "Verifying Vault cluster health in namespace '$NAMESPACE'..."

# Main verification loop
while [ $(($(date +%s) - START_TIME)) -lt $TIMEOUT ]; do
  ALL_HEALTHY=true
  log_info "Checking Vault pods..."
  
  # Get list of Vault pods
  VAULT_PODS=($(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}'))
  
  if [ ${#VAULT_PODS[@]} -eq 0 ]; then
    log_error "No Vault pods found in namespace '$NAMESPACE'"
    exit 1
  fi
  
  # Check each Vault pod
  for pod in "${VAULT_PODS[@]}"; do
    log_info "Checking pod: $pod"
    
    # Get Vault status
    STATUS_JSON=$(get_vault_status "$pod" "$NAMESPACE")
    
    if [ -z "$STATUS_JSON" ] || [ "$STATUS_JSON" = "{}" ]; then
      log_warning "Failed to get status from pod '$pod'"
      ALL_HEALTHY=false
      continue
    fi
    
    # Parse status
    INITIALIZED=$(echo "$STATUS_JSON" | jq -r '.initialized // "unknown"')
    SEALED=$(echo "$STATUS_JSON" | jq -r '.sealed // "unknown"')
    VERSION=$(echo "$STATUS_JSON" | jq -r '.version // "unknown"')
    HA_ENABLED=$(echo "$STATUS_JSON" | jq -r '.ha_enabled // "unknown"')
    ACTIVE_NODE=$(echo "$STATUS_JSON" | jq -r '.active_node // false')
    
    # Log status
    STATUS_LINE="Pod $pod: v$VERSION, initialized: $INITIALIZED, sealed: $SEALED, HA: $HA_ENABLED"
    
    if [ "$ACTIVE_NODE" != "false" ]; then
      STATUS_LINE="$STATUS_LINE (Active Node)"
    fi
    
    log_info "$STATUS_LINE"
    
    # Check for issues
    if [ "$INITIALIZED" != "true" ] || [ "$SEALED" != "false" ]; then
      ALL_HEALTHY=false
    fi
  done
  
  # If all pods are healthy, exit successfully
  if $ALL_HEALTHY; then
    log_info "All Vault pods are healthy and unsealed."
    
    # Additional check for HA status if HA is enabled
    if [ "$HA_ENABLED" = "true" ]; then
      log_info "Verifying HA status..."
      
      # Get the active node
      ACTIVE_NODE=$(oc exec -n "$NAMESPACE" "${VAULT_PODS[0]}" -- sh -c \
        "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null | \
        jq -r '.active_node // empty')
      
      if [ -n "$ACTIVE_NODE" ]; then
        log_info "HA cluster is healthy. Active node: $ACTIVE_NODE"
      else
        log_warning "Could not determine active node in HA cluster"
      fi
    fi
    
    exit 0
  fi
  
  log_info "Waiting for all pods to be healthy and unsealed..."
  sleep 5
done

# If we get here, the timeout was reached
log_error "Timed out waiting for Vault cluster to become healthy."
log_info "Current Vault pod status:"
oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o wide
exit 1
