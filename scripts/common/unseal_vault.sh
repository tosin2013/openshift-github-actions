#!/bin/bash
set -e

# Check if required parameters are provided
if [ $# -lt 4 ]; then
  echo "Usage: $0 <namespace> <key1> <key2> <key3> [key4] [key5]"
  echo "At least 3 unseal keys are required."
  exit 1
fi

NAMESPACE="$1"
shift
UNSEAL_KEYS=("$@")
MIN_KEYS=3

log_info() {
  echo "ℹ️  $1"
}

log_warning() {
  echo "⚠️  $1"
}

log_error() {
  echo "::error::$1" >&2
  exit 1
}

# Function to check if Vault is unsealed
is_vault_unsealed() {
  local pod=$1
  local namespace=$2
  
  if oc exec -n "$namespace" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json" 2>/dev/null | \
     jq -e '.sealed == false' >/dev/null 2>&1; then
    return 0  # Vault is unsealed
  else
    return 1  # Vault is sealed or error occurred
  fi
}

# Function to unseal a Vault pod
unseal_vault_pod() {
  local pod=$1
  local namespace=$2
  
  log_info "Unsealing Vault pod: $pod"
  
  # Check if already unsealed
  if is_vault_unsealed "$pod" "$namespace"; then
    log_info "Vault pod '$pod' is already unsealed."
    return 0
  fi
  
  # Try to unseal with the provided keys
  local unseal_success=false
  local keys_used=0
  
  for key in "${UNSEAL_KEYS[@]}"; do
    log_info "Applying unseal key to pod '$pod'..."
    
    # Run the unseal command
    if oc exec -n "$namespace" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator unseal $key" 2>&1 | grep -q 'Error'; then
      log_warning "Failed to apply unseal key to pod '$pod'"
    else
      ((keys_used++))
      log_info "Successfully applied unseal key to pod '$pod'"
    fi
    
    # Check if Vault is now unsealed
    if is_vault_unsealed "$pod" "$namespace"; then
      log_info "Successfully unsealed Vault pod: $pod"
      unseal_success=true
      break
    fi
  done
  
  # Verify unseal status
  if ! $unseal_success; then
    log_warning "Failed to unseal Vault pod '$pod' after $keys_used key(s)"
    return 1
  fi
  
  return 0
}

# Main execution
log_info "Starting Vault unseal process in namespace '$NAMESPACE'..."

# Get list of Vault pods
VAULT_PODS=($(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}'))

if [ ${#VAULT_PODS[@]} -eq 0 ]; then
  log_error "No Vault pods found in namespace '$NAMESPACE'"
fi

log_info "Found ${#VAULT_PODS[@]} Vault pod(s) in namespace '$NAMESPACE'"

# Unseal each Vault pod
UNSEALED_PODS=0
for pod in "${VAULT_PODS[@]}"; do
  if unseal_vault_pod "$pod" "$NAMESPACE"; then
    ((UNSEALED_PODS++))
  fi
done

# Verify all pods are unsealed
if [ "$UNSEALED_PODS" -eq "${#VAULT_PODS[@]}" ]; then
  log_info "Successfully unsealed all ${#VAULT_PODS[@]} Vault pod(s) in namespace '$NAMESPACE'"
  exit 0
else
  log_error "Failed to unseal all Vault pods. Unsealed $UNSEALED_PODS out of ${#VAULT_PODS[@]} pods."
fi
