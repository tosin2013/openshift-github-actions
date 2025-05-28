#!/bin/bash
set -e

# Check if required parameters are provided
if [ $# -lt 2 ]; then
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

# Function to initialize Vault
initialize_vault() {
  local pod=$1
  
  log_info "Initializing Vault on pod: $pod"
  
  # Initialize Vault with 5 keys and threshold of 3
  local init_output
  init_output=$(oc exec -n "$NAMESPACE" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator init -key-shares=5 -key-threshold=3 -format=json" 2>/dev/null)
  
  if [ $? -ne 0 ]; then
    log_warning "Failed to initialize Vault on pod $pod"
    return 1
  fi
  
  echo "$init_output"
  return 0
}

# Function to unseal a Vault pod
unseal_vault_pod() {
  local pod=$1
  
  log_info "Unsealing Vault pod: $pod"
  
  # Check if already unsealed
  if is_vault_unsealed "$pod"; then
    log_info "Vault pod '$pod' is already unsealed."
    return 0
  fi
  
  # Try to unseal with the provided keys
  local unseal_success=false
  local keys_used=0
  
  for key in "${UNSEAL_KEYS[@]}"; do
    log_info "Applying unseal key to pod '$pod'..."
    
    # Run the unseal command
    if ! oc exec -n "$NAMESPACE" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator unseal $key" 2>/dev/null; then
      log_warning "Failed to apply unseal key to pod '$pod'"
    else
      ((keys_used++))
      log_info "Successfully applied unseal key to pod '$pod'"
    fi
    
    # Check if Vault is now unsealed
    if is_vault_unsealed "$pod"; then
      log_info "✅ Successfully unsealed Vault pod: $pod"
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

# Function to join Raft cluster
join_raft_cluster() {
  local pod=$1
  local leader_pod=$2
  
  log_info "Joining pod $pod to Raft cluster via $leader_pod"
  
  # Get the leader's pod IP
  local leader_ip
  leader_ip=$(oc get pod -n "$NAMESPACE" "$leader_pod" -o jsonpath='{.status.podIP}')
  
  if [ -z "$leader_ip" ]; then
    log_warning "Could not get IP address for leader pod $leader_pod"
    return 1
  fi
  
  log_info "Joining $pod to Raft leader at $leader_ip:8200"
  
  # Join the Raft cluster
  if ! oc exec -n "$NAMESPACE" "$pod" -- sh -c "VAULT_ADDR=http://localhost:8200 VAULT_SKIP_VERIFY=true vault operator raft join http://$leader_ip:8200" 2>/dev/null; then
    log_warning "Failed to join Raft cluster for pod $pod"
    return 1
  fi
  
  log_info "Successfully joined pod $pod to Raft cluster"
  return 0
}

# Main execution
log_info "Starting Vault initialization and unseal process in namespace '$NAMESPACE'..."

# Get list of Vault pods sorted by name (vault-0, vault-1, etc.)
VAULT_PODS=($(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/name=vault --sort-by=.metadata.name -o jsonpath='{.items[*].metadata.name}'))

if [ ${#VAULT_PODS[@]} -eq 0 ]; then
  log_error "No Vault pods found in namespace '$NAMESPACE'"
fi

log_info "Found ${#VAULT_PODS[@]} Vault pod(s) in namespace '$NAMESPACE': ${VAULT_PODS[*]}"

# Check if Vault is already initialized
PRIMARY_POD="vault-0"
if is_vault_initialized "$PRIMARY_POD"; then
  log_info "Vault is already initialized on $PRIMARY_POD"
else
  # Initialize Vault on the primary pod
  log_info "Initializing Vault on primary pod: $PRIMARY_POD"
  init_output=$(initialize_vault "$PRIMARY_POD")
  
  if [ $? -ne 0 ]; then
    log_error "Failed to initialize Vault on primary pod $PRIMARY_POD"
  fi
  
  # Extract unseal keys and root token
  UNSEAL_KEYS=($(echo "$init_output" | jq -r '.unseal_keys_b64[]'))
  ROOT_TOKEN=$(echo "$init_output" | jq -r '.root_token')
  
  log_info "Vault initialized successfully on $PRIMARY_POD"
  log_info "Root Token: $ROOT_TOKEN"
  log_info "Unseal Keys: ${UNSEAL_KEYS[*]}"
  
  # Save the root token and unseal keys to GitHub outputs
  echo "root_token=$ROOT_TOKEN" >> $GITHUB_OUTPUT
  for i in "${!UNSEAL_KEYS[@]}"; do
    echo "unseal_key_$i=${UNSEAL_KEYS[$i]}" >> $GITHUB_OUTPUT
  done
fi

# Unseal the primary pod
log_info "Unsealing primary pod: $PRIMARY_POD"
if ! unseal_vault_pod "$PRIMARY_POD"; then
  log_error "Failed to unseal primary pod $PRIMARY_POD"
fi

# Wait for the primary pod to be fully unsealed and ready
log_info "Waiting for primary pod $PRIMARY_POD to be ready..."
for i in {1..30}; do
  if is_vault_unsealed "$PRIMARY_POD"; then
    log_info "Primary pod $PRIMARY_POD is ready"
    break
  fi
  
  if [ $i -eq 30 ]; then
    log_error "Timed out waiting for primary pod $PRIMARY_POD to be ready"
  fi
  
  sleep 2
done

# Process the remaining pods
for pod in "${VAULT_PODS[@]}"; do
  # Skip the primary pod as we've already processed it
  if [ "$pod" = "$PRIMARY_POD" ]; then
    continue
  fi
  
  log_info "Processing secondary node: $pod"
  
  # Join the Raft cluster
  if ! join_raft_cluster "$pod" "$PRIMARY_POD"; then
    log_warning "Failed to join Raft cluster for pod $pod, but continuing..."
  fi
  
  # Unseal the pod
  if ! unseal_vault_pod "$pod"; then
    log_warning "Failed to unseal pod $pod, but continuing..."
  fi
done

# Final verification
log_info "Verifying Vault cluster status..."
UNSEALED_PODS=0
for pod in "${VAULT_PODS[@]}"; do
  if is_vault_unsealed "$pod"; then
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
