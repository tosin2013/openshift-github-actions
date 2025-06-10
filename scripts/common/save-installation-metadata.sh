#!/bin/bash

# Save OpenShift installation metadata to HashiCorp Vault
# This enables cluster deletion without requiring the original installation-dir
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

Save OpenShift installation metadata to HashiCorp Vault for secure cluster lifecycle management.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --environment ENV           Environment (dev, staging, production)
  --installation-dir DIR      Installation directory (default: installation-dir)
  --help                      Show this help message

EXAMPLES:
  # Save AWS cluster installation metadata
  $0 --provider aws --cluster-name my-cluster --region us-east-1

  # Save with custom installation directory
  $0 --provider azure --cluster-name my-cluster --region eastus \\
     --installation-dir /path/to/install-dir

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

# Validate installation directory
if [ ! -d "$INSTALLATION_DIR" ]; then
  log "ERROR" "Installation directory not found: $INSTALLATION_DIR"
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

# Save terraform state to Vault
save_terraform_state() {
  log "INFO" "Saving Terraform state to Vault"
  
  local tf_state_path="$INSTALLATION_DIR/terraform.tfstate"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/terraform"
  
  if [ -f "$tf_state_path" ]; then
    local tf_state_b64=$(cat "$tf_state_path" | base64 -w 0)
    local tf_state_hash=$(sha256sum "$tf_state_path" | cut -d' ' -f1)
    
    vault_exec vault kv put "$vault_path" \
      terraform_state="$tf_state_b64" \
      state_hash="$tf_state_hash" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      created_by="${GITHUB_ACTOR:-$(whoami)}"
    
    log "INFO" "Terraform state saved to Vault: $vault_path"
  else
    log "WARN" "Terraform state file not found: $tf_state_path"
  fi
}

# Save cluster metadata to Vault
save_cluster_metadata() {
  log "INFO" "Saving cluster metadata to Vault"
  
  local metadata_path="$INSTALLATION_DIR/metadata.json"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/metadata"
  
  if [ -f "$metadata_path" ]; then
    local metadata_b64=$(cat "$metadata_path" | base64 -w 0)
    local metadata_hash=$(sha256sum "$metadata_path" | cut -d' ' -f1)
    
    vault_exec vault kv put "$vault_path" \
      cluster_metadata="$metadata_b64" \
      metadata_hash="$metadata_hash" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      created_by="${GITHUB_ACTOR:-$(whoami)}"
    
    log "INFO" "Cluster metadata saved to Vault: $vault_path"
  else
    log "WARN" "Cluster metadata file not found: $metadata_path"
  fi
}

# Save installation configuration
save_install_config() {
  log "INFO" "Saving installation configuration to Vault"
  
  local config_path="$INSTALLATION_DIR/install-config.yaml"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/config"
  
  if [ -f "$config_path" ]; then
    local config_b64=$(cat "$config_path" | base64 -w 0)
    local config_hash=$(sha256sum "$config_path" | cut -d' ' -f1)
    
    vault_exec vault kv put "$vault_path" \
      install_config="$config_b64" \
      config_hash="$config_hash" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      created_by="${GITHUB_ACTOR:-$(whoami)}"
    
    log "INFO" "Installation config saved to Vault: $vault_path"
  else
    log "WARN" "Installation config file not found: $config_path"
  fi
}

# Save infrastructure manifests
save_manifests() {
  log "INFO" "Saving infrastructure manifests to Vault"
  
  local manifests_dir="$INSTALLATION_DIR/manifests"
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/manifests"
  
  if [ -d "$manifests_dir" ]; then
    # Create a tarball of manifests
    local manifests_tar="/tmp/manifests-$CLUSTER_NAME.tar.gz"
    tar -czf "$manifests_tar" -C "$INSTALLATION_DIR" manifests/
    
    local manifests_b64=$(cat "$manifests_tar" | base64 -w 0)
    local manifests_hash=$(sha256sum "$manifests_tar" | cut -d' ' -f1)
    
    vault_exec vault kv put "$vault_path" \
      manifests_archive="$manifests_b64" \
      manifests_hash="$manifests_hash" \
      provider="$PROVIDER" \
      region="$REGION" \
      environment="$ENVIRONMENT" \
      created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      created_by="${GITHUB_ACTOR:-$(whoami)}"
    
    # Cleanup temporary file
    rm -f "$manifests_tar"
    
    log "INFO" "Infrastructure manifests saved to Vault: $vault_path"
  else
    log "WARN" "Manifests directory not found: $manifests_dir"
  fi
}

# Create installation summary
create_installation_summary() {
  log "INFO" "Creating installation summary"
  
  local vault_path="secret/openshift/clusters/$CLUSTER_NAME/installation/summary"
  
  # Gather file information
  local files_info=""
  if [ -f "$INSTALLATION_DIR/terraform.tfstate" ]; then
    files_info="$files_info,terraform_state:$(stat -c%s "$INSTALLATION_DIR/terraform.tfstate")"
  fi
  if [ -f "$INSTALLATION_DIR/metadata.json" ]; then
    files_info="$files_info,metadata:$(stat -c%s "$INSTALLATION_DIR/metadata.json")"
  fi
  if [ -f "$INSTALLATION_DIR/install-config.yaml" ]; then
    files_info="$files_info,install_config:$(stat -c%s "$INSTALLATION_DIR/install-config.yaml")"
  fi
  if [ -d "$INSTALLATION_DIR/manifests" ]; then
    files_info="$files_info,manifests:$(du -sb "$INSTALLATION_DIR/manifests" | cut -f1)"
  fi
  
  vault_exec vault kv put "$vault_path" \
    cluster_name="$CLUSTER_NAME" \
    provider="$PROVIDER" \
    region="$REGION" \
    environment="$ENVIRONMENT" \
    installation_files="${files_info#,}" \
    backup_completed="true" \
    backup_timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    backup_by="${GITHUB_ACTOR:-$(whoami)}" \
    vault_version="$(vault_exec vault version | head -1)"
  
  log "INFO" "Installation summary saved to Vault: $vault_path"
}

# Verify backup integrity
verify_backup() {
  log "INFO" "Verifying backup integrity"
  
  local paths=(
    "secret/openshift/clusters/$CLUSTER_NAME/installation/summary"
  )
  
  # Add paths based on what files exist
  if [ -f "$INSTALLATION_DIR/terraform.tfstate" ]; then
    paths+=("secret/openshift/clusters/$CLUSTER_NAME/installation/terraform")
  fi
  if [ -f "$INSTALLATION_DIR/metadata.json" ]; then
    paths+=("secret/openshift/clusters/$CLUSTER_NAME/installation/metadata")
  fi
  
  local verification_success=true
  
  for path in "${paths[@]}"; do
    if vault_exec vault kv get "$path" >/dev/null 2>&1; then
      log "INFO" "✅ Verified backup: $path"
    else
      log "ERROR" "❌ Failed to verify backup: $path"
      verification_success=false
    fi
  done
  
  if [[ "$verification_success" == "true" ]]; then
    log "INFO" "✅ All installation metadata backed up successfully"
  else
    log "ERROR" "❌ Backup verification failed"
    return 1
  fi
}

# Main function
main() {
  log "INFO" "Starting installation metadata backup to Vault"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Region: $REGION"
  log "INFO" "Environment: $ENVIRONMENT"
  log "INFO" "Installation Directory: $INSTALLATION_DIR"
  
  # Save all installation metadata
  save_terraform_state
  save_cluster_metadata
  save_install_config
  save_manifests
  create_installation_summary
  
  # Verify backup integrity
  verify_backup
  
  log "INFO" "Installation metadata backup completed successfully"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## 🔐 Installation Metadata Backed Up to Vault"
    add_to_step_summary "Successfully saved installation metadata to Vault for secure cluster lifecycle management"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Environment**: $ENVIRONMENT"
    add_to_step_summary ""
    add_to_step_summary "**Backed Up Items:**"
    add_to_step_summary "- Terraform state (encrypted)"
    add_to_step_summary "- Cluster metadata"
    add_to_step_summary "- Installation configuration"
    add_to_step_summary "- Infrastructure manifests"
    add_to_step_summary "- Installation summary"
  fi
  
  return 0
}

# Run main function
main "$@"
