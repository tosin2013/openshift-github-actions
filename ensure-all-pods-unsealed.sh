#!/bin/bash

# Ensure All Vault Pods Unsealed Script
# Author: Tosin Akinosho, Sophia AI Assistant
# Purpose: Automatically unseal all Vault pods to complete HA cluster setup

set -euo pipefail

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
NAMESPACE=${VAULT_NAMESPACE:-"vault-8q957"}
MAX_RETRIES=3
TIMEOUT_SECONDS=15

# Log function
log() {
  local level=$1
  local message=$2
  local color=$NC
  
  case $level in
    "INFO") color=$GREEN ;;
    "WARN") color=$YELLOW ;;
    "ERROR") color=$RED ;;
    "DEBUG") color=$BLUE ;;
  esac
  
  echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message${NC}"
}

# Load unseal keys
load_unseal_keys() {
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
    log "INFO" "Loaded unseal keys from vault-keys.env"
  else
    log "ERROR" "vault-keys.env not found. Cannot unseal pods."
    exit 1
  fi
  
  # Validate keys exist
  if [[ -z "${UNSEAL_KEY_1:-}" || -z "${UNSEAL_KEY_2:-}" || -z "${UNSEAL_KEY_3:-}" ]]; then
    log "ERROR" "Missing unseal keys in vault-keys.env"
    exit 1
  fi
}

# Detect protocol for a pod
detect_protocol() {
  local pod=$1

  # Try HTTPS first (with macOS timeout fallback)
  if (command -v timeout >/dev/null 2>&1 && timeout 5 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" >/dev/null 2>&1) || \
     (command -v gtimeout >/dev/null 2>&1 && gtimeout 5 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" >/dev/null 2>&1) || \
     oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=https://localhost:8200 vault status" >/dev/null 2>&1; then
    echo "https://localhost:8200"
    return 0
  fi

  # Try HTTP (with macOS timeout fallback)
  if (command -v timeout >/dev/null 2>&1 && timeout 5 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=http://localhost:8200 vault status" >/dev/null 2>&1) || \
     (command -v gtimeout >/dev/null 2>&1 && gtimeout 5 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=http://localhost:8200 vault status" >/dev/null 2>&1) || \
     oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=http://localhost:8200 vault status" >/dev/null 2>&1; then
    echo "http://localhost:8200"
    return 0
  fi

  # Default to HTTPS
  echo "https://localhost:8200"
  return 0
}

# Check if pod is unsealed
is_pod_unsealed() {
  local pod=$1
  local vault_addr
  vault_addr=$(detect_protocol "$pod")
  
  local status
  if [[ "$vault_addr" == "https://"* ]]; then
    if command -v timeout >/dev/null 2>&1; then
      status=$(timeout "$TIMEOUT_SECONDS" oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    elif command -v gtimeout >/dev/null 2>&1; then
      status=$(gtimeout "$TIMEOUT_SECONDS" oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    else
      status=$(oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    fi
  else
    if command -v timeout >/dev/null 2>&1; then
      status=$(timeout "$TIMEOUT_SECONDS" oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    elif command -v gtimeout >/dev/null 2>&1; then
      status=$(gtimeout "$TIMEOUT_SECONDS" oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    else
      status=$(oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault status -format=json" 2>/dev/null)
    fi
  fi
  
  if [[ $? -eq 0 && -n "$status" ]]; then
    local sealed
    sealed=$(echo "$status" | jq -r '.sealed // true' 2>/dev/null)
    if [[ "$sealed" == "false" ]]; then
      return 0  # Unsealed
    fi
  fi
  
  return 1  # Sealed or error
}

# Unseal a single pod
unseal_pod() {
  local pod=$1
  log "INFO" "Unsealing $pod..."
  
  # Check if already unsealed
  if is_pod_unsealed "$pod"; then
    log "INFO" "$pod is already unsealed"
    return 0
  fi
  
  local vault_addr
  vault_addr=$(detect_protocol "$pod")
  log "DEBUG" "Using $vault_addr for $pod"
  
  # Apply unseal keys
  local success=true
  
  if [[ "$vault_addr" == "https://"* ]]; then
    # HTTPS unsealing (with macOS timeout fallback)
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_1" >/dev/null 2>&1 || success=false
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_2" >/dev/null 2>&1 || success=false
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_3" >/dev/null 2>&1 || success=false
  else
    # HTTP unsealing (with macOS timeout fallback)
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_1" >/dev/null 2>&1 || success=false
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_2" >/dev/null 2>&1 || success=false
    oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault operator unseal $UNSEAL_KEY_3" >/dev/null 2>&1 || success=false
  fi
  
  if [[ "$success" == "true" ]]; then
    # Wait a moment and verify
    sleep 3
    if is_pod_unsealed "$pod"; then
      log "INFO" "✅ $pod successfully unsealed"
      return 0
    else
      log "WARN" "⚠️  $pod unseal commands completed but pod still appears sealed"
      return 1
    fi
  else
    log "ERROR" "❌ Failed to apply unseal keys to $pod"
    return 1
  fi
}

# Ensure all pods are unsealed
ensure_all_unsealed() {
  log "INFO" "Ensuring all Vault pods are unsealed..."
  
  local pods=("vault-0" "vault-1" "vault-2")
  local unsealed_count=0
  local total_pods=0
  
  for pod in "${pods[@]}"; do
    # Check if pod exists
    if ! oc get pod "$pod" -n "$NAMESPACE" >/dev/null 2>&1; then
      log "WARN" "Pod $pod not found, skipping..."
      continue
    fi
    
    total_pods=$((total_pods + 1))
    
    # Try to unseal with retries
    local retry_count=0
    local unsealed=false
    
    while [[ $retry_count -lt $MAX_RETRIES ]]; do
      if unseal_pod "$pod"; then
        unsealed=true
        break
      fi
      
      retry_count=$((retry_count + 1))
      if [[ $retry_count -lt $MAX_RETRIES ]]; then
        log "WARN" "Retry $retry_count/$MAX_RETRIES for $pod in 5 seconds..."
        sleep 5
      fi
    done
    
    if [[ "$unsealed" == "true" ]]; then
      unsealed_count=$((unsealed_count + 1))
    else
      log "ERROR" "Failed to unseal $pod after $MAX_RETRIES attempts"
    fi
  done
  
  log "INFO" "Unsealing summary: $unsealed_count/$total_pods pods unsealed"
  
  if [[ $unsealed_count -eq $total_pods && $total_pods -eq 3 ]]; then
    log "INFO" "🎉 SUCCESS: All Vault pods are unsealed! HA cluster is fully operational."
    return 0
  elif [[ $unsealed_count -gt 0 ]]; then
    log "WARN" "⚠️  PARTIAL: $unsealed_count/$total_pods pods unsealed. HA cluster partially operational."
    return 1
  else
    log "ERROR" "❌ FAILED: No pods could be unsealed. HA cluster not operational."
    return 2
  fi
}

# Verify HA cluster status
verify_ha_status() {
  log "INFO" "Verifying HA cluster status..."
  
  for pod in vault-0 vault-1 vault-2; do
    if oc get pod "$pod" -n "$NAMESPACE" >/dev/null 2>&1; then
      local vault_addr
      vault_addr=$(detect_protocol "$pod")
      
      local status
      if [[ "$vault_addr" == "https://"* ]]; then
        status=$(timeout 10 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_SKIP_VERIFY=true VAULT_ADDR=$vault_addr vault status" 2>/dev/null | grep -E "(Initialized|Sealed|HA Mode)" || echo "Status check failed")
      else
        status=$(timeout 10 oc exec "$pod" -n "$NAMESPACE" -- sh -c "VAULT_ADDR=$vault_addr vault status" 2>/dev/null | grep -E "(Initialized|Sealed|HA Mode)" || echo "Status check failed")
      fi
      
      log "INFO" "$pod status:"
      echo "$status" | while read -r line; do
        log "INFO" "  $line"
      done
    fi
  done
}

# Main function
main() {
  echo -e "${BLUE}"
  echo "=================================================================="
  echo "    Ensure All Vault Pods Unsealed"
  echo "=================================================================="
  echo -e "${NC}"
  echo "Namespace: $NAMESPACE"
  echo "Max Retries: $MAX_RETRIES"
  echo "Timeout: $TIMEOUT_SECONDS seconds"
  echo ""
  
  load_unseal_keys
  
  local exit_code=0
  ensure_all_unsealed || exit_code=$?
  
  echo ""
  verify_ha_status
  
  echo ""
  echo -e "${BLUE}=================================================================="
  if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}✅ All pods successfully unsealed! HA cluster ready.${NC}"
  elif [[ $exit_code -eq 1 ]]; then
    echo -e "${YELLOW}⚠️  Partial success. Some pods may need manual attention.${NC}"
  else
    echo -e "${RED}❌ Failed to unseal pods. Manual intervention required.${NC}"
  fi
  echo -e "${BLUE}==================================================================${NC}"
  
  exit $exit_code
}

# Script execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
