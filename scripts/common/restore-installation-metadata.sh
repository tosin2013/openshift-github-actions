#!/bin/bash

# Restore OpenShift installation metadata from HashiCorp Vault
# This enables cluster deletion by reconstructing the installation-dir
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
INSTALLATION_DIR="installation-dir"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault-test-pragmatic}"
VAULT_POD="${VAULT_POD:-vault-0}"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Restore OpenShift installation metadata from HashiCorp Vault to enable cluster deletion.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --environment ENV           Environment (dev, staging, production)
  --installation-dir DIR      Installation directory to restore (default: installation-dir)
  --help                      Show this help message

EXAMPLES:
  # Restore AWS cluster installation metadata
  $0 --provider aws --cluster-name my-cluster --region us-east-1

  # Restore to custom directory
  $0 --provider azure --cluster-name my-cluster --region eastus \\
     --installation-dir /path/to/restore-dir

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
    --installation-dir)
      INSTALLATION_DIR="$2"
      shift 2
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
  
  oc exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -- sh -c "
    export VAULT_TOKEN='$vault_token'
    export VAULT_ADDR=https://localhost:8200
    export VAULT_SKIP_VERIFY=true
    $vault_command
  "
}

# Check if backup exists
check_backup_exists() {
  log "INFO" "Checking if installation backup exists in Vault"
  
  local summary_path="secret/openshift/clusters/$CLUSTER_NAME/installation/summary"
  
  if vault_exec vault kv get "$summary_path" >/dev/null 2>&1; then
    log "INFO" "✅ Installation backup found in Vault"
    return 0
  else
    log "ERROR" "❌ No installation backup found for cluster: $CLUSTER_NAME"
    log "ERROR" "Cannot restore installation metadata - backup does not exist"
    return 1
  fi
}

# Create installation directory structure
create_installation_dir() {
  log "INFO" "Creating installation directory structure"
  
  # Remove existing directory if it exists
  if [ -d "$INSTALLATION_DIR" ]; then
    log "WARN" "Removing existing installation directory: $INSTALLATION_DIR"
    rm -rf "$INSTALLATION_DIR"
  fi
  
  # Create directory structure
  mkdir -p "$INSTALLATION_DIR"/{auth,manifests}
  
  log "INFO" "Created installation directory: $INSTALLATION_DIR"
}

# Restore terraform state
restore_terraform_state() {
  log "INFO" "Restoring Terraform state from Vault"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/terraform"
  local tf_state_path="$INSTALLATION_DIR/terraform.tfstate"
  
  if vault_exec vault kv get -field=terraform_state "$vault_path" >/dev/null 2>&1; then
    local tf_state_b64=$(vault_exec vault kv get -field=terraform_state "$vault_path")
    local stored_hash=$(vault_exec vault kv get -field=state_hash "$vault_path" 2>/dev/null || echo "")
    
    # Decode and save terraform state
    echo "$tf_state_b64" | base64 -d > "$tf_state_path"
    
    # Verify integrity if hash is available
    if [[ -n "$stored_hash" ]]; then
      local current_hash=$(sha256sum "$tf_state_path" | cut -d' ' -f1)
      if [[ "$current_hash" == "$stored_hash" ]]; then
        log "INFO" "✅ Terraform state restored and verified: $tf_state_path"
      else
        log "WARN" "⚠️ Terraform state hash mismatch - file may be corrupted"
      fi
    else
      log "INFO" "✅ Terraform state restored: $tf_state_path"
    fi
  else
    log "WARN" "No Terraform state found in Vault backup"
  fi
}

# Restore cluster metadata
restore_cluster_metadata() {
  log "INFO" "Restoring cluster metadata from Vault"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/metadata"
  local metadata_path="$INSTALLATION_DIR/metadata.json"
  
  if vault_exec vault kv get -field=cluster_metadata "$vault_path" >/dev/null 2>&1; then
    local metadata_b64=$(vault_exec vault kv get -field=cluster_metadata "$vault_path")
    local stored_hash=$(vault_exec vault kv get -field=metadata_hash "$vault_path" 2>/dev/null || echo "")
    
    # Decode and save metadata
    echo "$metadata_b64" | base64 -d > "$metadata_path"
    
    # Verify integrity if hash is available
    if [[ -n "$stored_hash" ]]; then
      local current_hash=$(sha256sum "$metadata_path" | cut -d' ' -f1)
      if [[ "$current_hash" == "$stored_hash" ]]; then
        log "INFO" "✅ Cluster metadata restored and verified: $metadata_path"
      else
        log "WARN" "⚠️ Cluster metadata hash mismatch - file may be corrupted"
      fi
    else
      log "INFO" "✅ Cluster metadata restored: $metadata_path"
    fi
  else
    log "WARN" "No cluster metadata found in Vault backup"
  fi
}

# Restore installation config
restore_install_config() {
  log "INFO" "Restoring installation configuration from Vault"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/config"
  local config_path="$INSTALLATION_DIR/install-config.yaml"
  
  if vault_exec vault kv get -field=install_config "$vault_path" >/dev/null 2>&1; then
    local config_b64=$(vault_exec vault kv get -field=install_config "$vault_path")
    local stored_hash=$(vault_exec vault kv get -field=config_hash "$vault_path" 2>/dev/null || echo "")
    
    # Decode and save config
    echo "$config_b64" | base64 -d > "$config_path"
    
    # Verify integrity if hash is available
    if [[ -n "$stored_hash" ]]; then
      local current_hash=$(sha256sum "$config_path" | cut -d' ' -f1)
      if [[ "$current_hash" == "$stored_hash" ]]; then
        log "INFO" "✅ Installation config restored and verified: $config_path"
      else
        log "WARN" "⚠️ Installation config hash mismatch - file may be corrupted"
      fi
    else
      log "INFO" "✅ Installation config restored: $config_path"
    fi
  else
    log "WARN" "No installation config found in Vault backup"
  fi
}

# Restore manifests
restore_manifests() {
  log "INFO" "Restoring infrastructure manifests from Vault"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/manifests"
  
  if vault_exec vault kv get -field=manifests_archive "$vault_path" >/dev/null 2>&1; then
    local manifests_b64=$(vault_exec vault kv get -field=manifests_archive "$vault_path")
    local stored_hash=$(vault_exec vault kv get -field=manifests_hash "$vault_path" 2>/dev/null || echo "")
    
    # Decode and extract manifests
    local manifests_tar="/tmp/manifests-restore-$CLUSTER_NAME.tar.gz"
    echo "$manifests_b64" | base64 -d > "$manifests_tar"
    
    # Verify integrity if hash is available
    if [[ -n "$stored_hash" ]]; then
      local current_hash=$(sha256sum "$manifests_tar" | cut -d' ' -f1)
      if [[ "$current_hash" == "$stored_hash" ]]; then
        log "INFO" "✅ Manifests archive verified"
      else
        log "WARN" "⚠️ Manifests archive hash mismatch - file may be corrupted"
      fi
    fi
    
    # Extract manifests
    tar -xzf "$manifests_tar" -C "$INSTALLATION_DIR"
    
    # Cleanup temporary file
    rm -f "$manifests_tar"
    
    log "INFO" "✅ Infrastructure manifests restored: $INSTALLATION_DIR/manifests"
  else
    log "WARN" "No infrastructure manifests found in Vault backup"
  fi
}

# Display restoration summary
display_summary() {
  log "INFO" "Displaying restoration summary"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/summary"
  
  if vault_exec vault kv get "$vault_path" >/dev/null 2>&1; then
    local backup_timestamp=$(vault_exec vault kv get -field=backup_timestamp "$vault_path" 2>/dev/null || echo "unknown")
    local backup_by=$(vault_exec vault kv get -field=backup_by "$vault_path" 2>/dev/null || echo "unknown")
    local installation_files=$(vault_exec vault kv get -field=installation_files "$vault_path" 2>/dev/null || echo "")
    
    log "INFO" "📋 Restoration Summary:"
    log "INFO" "  - Cluster: $CLUSTER_NAME"
    log "INFO" "  - Provider: $PROVIDER"
    log "INFO" "  - Region: $REGION"
    log "INFO" "  - Backup Date: $backup_timestamp"
    log "INFO" "  - Backup By: $backup_by"
    log "INFO" "  - Restored To: $INSTALLATION_DIR"
    
    if [[ -n "$installation_files" ]]; then
      log "INFO" "  - Files: $installation_files"
    fi
  fi
}

# Verify restoration
verify_restoration() {
  log "INFO" "Verifying restoration completeness"
  
  local verification_success=true
  local restored_files=0
  
  # Check for key files
  if [ -f "$INSTALLATION_DIR/terraform.tfstate" ]; then
    log "INFO" "✅ Terraform state restored"
    ((restored_files++))
  else
    log "WARN" "⚠️ Terraform state not restored"
  fi
  
  if [ -f "$INSTALLATION_DIR/metadata.json" ]; then
    log "INFO" "✅ Cluster metadata restored"
    ((restored_files++))
  else
    log "WARN" "⚠️ Cluster metadata not restored"
  fi
  
  if [ -f "$INSTALLATION_DIR/install-config.yaml" ]; then
    log "INFO" "✅ Installation config restored"
    ((restored_files++))
  else
    log "WARN" "⚠️ Installation config not restored"
  fi
  
  if [ -d "$INSTALLATION_DIR/manifests" ]; then
    log "INFO" "✅ Infrastructure manifests restored"
    ((restored_files++))
  else
    log "WARN" "⚠️ Infrastructure manifests not restored"
  fi
  
  if [[ $restored_files -gt 0 ]]; then
    log "INFO" "✅ Restoration completed - $restored_files file(s) restored"
    log "INFO" "Installation directory is ready for cluster deletion"
  else
    log "ERROR" "❌ No files were restored - cluster deletion may fail"
    verification_success=false
  fi
  
  return $([[ "$verification_success" == "true" ]] && echo 0 || echo 1)
}

# Main function
main() {
  log "INFO" "Starting installation metadata restoration from Vault"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Region: $REGION"
  log "INFO" "Environment: $ENVIRONMENT"
  log "INFO" "Target Directory: $INSTALLATION_DIR"
  
  # Check if backup exists
  check_backup_exists
  
  # Create installation directory
  create_installation_dir
  
  # Restore all installation metadata
  restore_terraform_state
  restore_cluster_metadata
  restore_install_config
  restore_manifests
  
  # Display summary and verify
  display_summary
  verify_restoration
  
  log "INFO" "Installation metadata restoration completed"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## 🔓 Installation Metadata Restored from Vault"
    add_to_step_summary "Successfully restored installation metadata from Vault for cluster deletion"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Restored To**: $INSTALLATION_DIR"
    add_to_step_summary ""
    add_to_step_summary "**Restored Items:**"
    add_to_step_summary "- Terraform state"
    add_to_step_summary "- Cluster metadata"
    add_to_step_summary "- Installation configuration"
    add_to_step_summary "- Infrastructure manifests"
  fi
  
  return 0
}

# Run main function
main "$@"
