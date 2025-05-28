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

# Function to get Vault status
get_vault_status() {
  local pod=$1
  oc exec -n "$NAMESPACE" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault status -format=json 2>/dev/null" || echo "{}"
}

# Function to check if Vault is unsealed
is_vault_unsealed() {
  local pod=$1
  local status
  status=$(get_vault_status "$pod")
  echo "$status" | jq -e '.sealed == false' >/dev/null 2>&1
  return $?
}

# Function to check if Vault is initialized
is_vault_initialized() {
  local pod=$1
  local status
  status=$(get_vault_status "$pod")
  echo "$status" | jq -e '.initialized == true' >/dev/null 2>&1
  return $?
}

# Function to get the active node's Raft address
get_active_node_raft_address() {
  local pod=$1
  local status
  status=$(get_vault_status "$pod")
  if echo "$status" | jq -e '.sealed == false' >/dev/null; then
    echo "$status" | jq -r '.storage_type + "@" + .cluster_address' 2>/dev/null || echo ""
  else
    echo ""
  fi
}

# Function to join Raft cluster
join_raft_cluster() {
  local pod=$1
  local leader_pod=$2
  
  log_info "Joining pod $pod to Raft cluster via $leader_pod"
  
  # Get the active node's Raft address
  local leader_addr
  leader_addr=$(get_active_node_raft_address "$leader_pod")
  
  if [ -z "$leader_addr" ]; then
    log_warning "Could not get leader's Raft address from $leader_pod"
    return 1
  fi
  
  # Extract the address part (remove the raft@ prefix if present)
  leader_addr=${leader_addr#*@}
  
  log_info "Joining $pod to Raft leader at $leader_addr"
  
  # Join the Raft cluster
  if ! oc exec -n "$NAMESPACE" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator raft join http://$leader_addr" 2>/dev/null; then
    log_warning "Failed to join Raft cluster for pod $pod"
    return 1
  fi
  
  return 0
}

# Function to unseal a Vault pod
unseal_vault_pod() {
  local pod=$1
  local namespace=$2
  
  log_info "Processing Vault pod: $pod"
  
  # Check if already unsealed
  if is_vault_unsealed "$pod" "$namespace"; then
    log_info "Vault pod '$pod' is already unsealed."
    return 0
  fi
  
  # Check if initialized
  if ! is_vault_initialized "$pod"; then
    log_info "Vault pod '$pod' is not initialized. It will be initialized when joining the cluster."
    return 0
  fi
  
  # Try to unseal with the provided keys
  local unseal_success=false
  local keys_used=0
  
  for key in "${UNSEAL_KEYS[@]}"; do
    log_info "Applying unseal key to pod '$pod'..."
    
    # Run the unseal command
    if ! oc exec -n "$namespace" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator unseal $key" 2>/dev/null; then
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
  
  if ! $unseal_success; then
    log_warning "Failed to unseal Vault pod '$pod' after $keys_used key(s)"
    return 1
  fi
  
  return 0
}

# Main execution
log_info "Starting Vault unseal process in namespace '$NAMESPACE'..."

# Get list of Vault pods sorted by name (vault-0, vault-1, etc.)
VAULT_PODS=($(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault --sort-by=.metadata.name -o jsonpath='{.items[*].metadata.name}'))

if [ ${#VAULT_PODS[@]} -eq 0 ]; then
  log_error "No Vault pods found in namespace '$NAMESPACE'"
fi

log_info "Found ${#VAULT_PODS[@]} Vault pod(s) in namespace '$NAMESPACE'"

# First, try to unseal vault-0 (the primary node)
PRIMARY_POD="vault-0"
log_info "Processing primary node: $PRIMARY_POD"
if ! unseal_vault_pod "$PRIMARY_POD" "$NAMESPACE"; then
  log_error "Failed to unseal primary Vault pod $PRIMARY_POD. Cannot continue."
fi

# Now process the remaining pods
for pod in "${VAULT_PODS[@]}"; do
  # Skip the primary pod as we've already processed it
  if [ "$pod" = "$PRIMARY_POD" ]; then
    continue
  fi
  
  log_info "Processing secondary node: $pod"
  
  # First, join the Raft cluster
  if ! join_raft_cluster "$pod" "$PRIMARY_POD"; then
    log_warning "Failed to join Raft cluster for pod $pod, but continuing..."
  fi
  
  # Then unseal the pod
  if ! unseal_vault_pod "$pod" "$NAMESPACE"; then
    log_warning "Failed to unseal pod $pod, but continuing..."
  fi
done

# Final verification
log_info "Verifying Vault cluster status..."
UNSEALED_PODS=0
for pod in "${VAULT_PODS[@]}"; do
  if is_vault_unsealed "$pod" "$NAMESPACE"; then
    ((UNSEALED_PODS++))
    log_info "✅ $pod is unsealed"
  else
    log_warning "❌ $pod is still sealed"
  fi
done

if [ "$UNSEALED_PODS" -eq "${#VAULT_PODS[@]}" ]; then
  log_info "✅ Successfully unsealed all ${#VAULT_PODS[@]} Vault pod(s) in namespace '$NAMESPACE'"
  exit 0
else
  log_warning "⚠️  Only unsealed $UNSEALED_PODS out of ${#VAULT_PODS[@]} Vault pods. Some pods may need manual intervention."
  exit 1
fi
