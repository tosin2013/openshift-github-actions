#!/bin/bash

# Remove cluster credentials and data from HashiCorp Vault
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
REGION=""
ENVIRONMENT="dev"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault-test-pragmatic}"
VAULT_POD="${VAULT_POD:-vault-0}"
DRY_RUN=false

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Remove OpenShift cluster credentials and data from HashiCorp Vault.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --environment ENV           Environment (dev, staging, production)
  --dry-run                   Show what would be deleted without actually deleting
  --help                      Show this help message

EXAMPLES:
  # Remove AWS cluster data from Vault
  $0 --provider aws --cluster-name my-cluster --region us-east-1

  # Dry run to see what would be deleted
  $0 --provider aws --cluster-name my-cluster --region us-east-1 --dry-run

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --provider)
      PROVIDER="$2"
      shift 2
      ;;
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      log "ERROR" "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$PROVIDER" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Get Vault root token
get_vault_token() {
  # Try to get token from vault-keys.env
  if [[ -f "vault-keys.env" ]]; then
    source vault-keys.env
    if [[ -n "${VAULT_ROOT_TOKEN:-}" ]]; then
      echo "$VAULT_ROOT_TOKEN"
      return 0
    elif [[ -n "${ROOT_TOKEN:-}" ]]; then
      echo "$ROOT_TOKEN"
      return 0
    fi
  fi
  
  log "ERROR" "Could not find Vault root token in vault-keys.env"
  exit 1
}

# Execute vault command in Kubernetes pod
vault_exec() {
  local vault_token=$(get_vault_token)
  local vault_command="$*"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would execute: $vault_command"
    return 0
  fi
  
  oc exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$vault_token'
    export VAULT_ADDR=https://localhost:8200
    export VAULT_SKIP_VERIFY=true
    $vault_command
  "
}

# List cluster data in Vault
list_cluster_data() {
  log "INFO" "Listing cluster data in Vault for: $CLUSTER_NAME"
  
  local paths=(
    "secret/openshift/clusters/$CLUSTER_NAME"
    "secret/openshift/inventory/$ENVIRONMENT/$PROVIDER"
  )
  
  for path in "${paths[@]}"; do
    log "INFO" "Checking path: $path"
    if vault_exec vault kv list "$path" 2>/dev/null; then
      log "INFO" "Found data at: $path"
    else
      log "INFO" "No data found at: $path"
    fi
  done
}

# Revoke dynamic AWS credentials
revoke_dynamic_credentials() {
  log "INFO" "Revoking dynamic AWS credentials for cluster: $CLUSTER_NAME"
  
  # List active leases for the cluster
  if vault_exec vault list sys/leases/lookup/aws/creds/openshift-installer 2>/dev/null; then
    log "INFO" "Found active AWS credential leases"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log "INFO" "[DRY RUN] Would revoke AWS credential leases"
    else
      vault_exec vault lease revoke -prefix aws/creds/openshift-installer/
      log "INFO" "Revoked AWS credential leases"
    fi
  else
    log "INFO" "No active AWS credential leases found"
  fi
}

# Remove cluster credentials
remove_cluster_credentials() {
  log "INFO" "Removing cluster credentials from Vault"
  
  local paths=(
    "secret/openshift/clusters/$CLUSTER_NAME/kubeconfig"
    "secret/openshift/clusters/$CLUSTER_NAME/kubeadmin"
    "secret/openshift/clusters/$CLUSTER_NAME/metadata"
    "secret/openshift/clusters/$CLUSTER_NAME/logs"
    "secret/openshift/clusters/$CLUSTER_NAME/terraform"
  )
  
  for path in "${paths[@]}"; do
    if [[ "$DRY_RUN" == "true" ]]; then
      log "INFO" "[DRY RUN] Would delete: $path"
    else
      if vault_exec vault kv delete "$path" 2>/dev/null; then
        log "INFO" "Deleted: $path"
      else
        log "WARN" "Failed to delete or not found: $path"
      fi
    fi
  done
}

# Update cluster inventory
update_cluster_inventory() {
  log "INFO" "Updating cluster inventory"
  
  local inventory_path="secret/openshift/inventory/$ENVIRONMENT/$PROVIDER"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "[DRY RUN] Would update inventory at: $inventory_path"
    return 0
  fi
  
  # This is a simplified approach - in production, you'd use jq to properly update JSON
  log "WARN" "Cluster inventory update not implemented - manual cleanup may be required"
  log "INFO" "Please manually review inventory at: $inventory_path"
}

# Verify cleanup
verify_cleanup() {
  log "INFO" "Verifying cluster data removal"
  
  local paths=(
    "secret/openshift/clusters/$CLUSTER_NAME/kubeconfig"
    "secret/openshift/clusters/$CLUSTER_NAME/kubeadmin"
    "secret/openshift/clusters/$CLUSTER_NAME/metadata"
  )
  
  local cleanup_success=true
  
  for path in "${paths[@]}"; do
    if vault_exec vault kv get "$path" >/dev/null 2>&1; then
      log "ERROR" "❌ Data still exists: $path"
      cleanup_success=false
    else
      log "INFO" "✅ Confirmed deleted: $path"
    fi
  done
  
  if [[ "$cleanup_success" == "true" ]]; then
    log "INFO" "✅ Vault cleanup verification successful"
  else
    log "ERROR" "❌ Vault cleanup verification failed"
    return 1
  fi
}

# Main function
main() {
  log "INFO" "Starting Vault cleanup for cluster: $CLUSTER_NAME"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Region: $REGION"
  log "INFO" "Environment: $ENVIRONMENT"
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log "INFO" "🔍 DRY RUN MODE - No actual changes will be made"
  fi
  
  # List what we have
  list_cluster_data
  
  # Revoke dynamic credentials
  revoke_dynamic_credentials
  
  # Remove cluster data
  remove_cluster_credentials
  
  # Update inventory
  update_cluster_inventory
  
  # Verify cleanup (skip for dry run)
  if [[ "$DRY_RUN" == "false" ]]; then
    verify_cleanup
  fi
  
  log "INFO" "Vault cleanup completed for cluster: $CLUSTER_NAME"
  
  return 0
}

# Run main function
main "$@"
