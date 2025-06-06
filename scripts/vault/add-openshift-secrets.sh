#!/bin/bash

# Add OpenShift secrets to Vault for deployment workflows
# This script adds the required secrets that the deploy-aws.yml workflow expects

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [WARNING]${NC} $1"
}

# Check if running in OpenShift
if ! oc whoami &>/dev/null; then
    error "Not logged into OpenShift. Please run 'oc login' first."
    exit 1
fi

# Vault configuration
VAULT_NAMESPACE="vault-test-pragmatic"
VAULT_POD="vault-0"

log "Adding OpenShift secrets to Vault..."

# Function to check if Vault is ready and authenticate
check_vault_status() {
    log "Checking Vault status..."
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- vault status &>/dev/null; then
        success "Vault is accessible and ready"
    else
        error "Vault is not accessible or sealed"
        return 1
    fi

    # Authenticate with Vault using root token
    log "Authenticating with Vault..."
    local vault_keys_file="vault-keys.env"

    if [[ ! -f "$vault_keys_file" ]]; then
        error "Vault keys file not found: $vault_keys_file"
        return 1
    fi

    # Source the vault keys to get ROOT_TOKEN
    source "$vault_keys_file"

    if [[ -z "$ROOT_TOKEN" ]]; then
        error "ROOT_TOKEN not found in $vault_keys_file"
        return 1
    fi

    # Test authentication with Vault using token
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault token lookup &>/dev/null; then
        success "Successfully authenticated with Vault"
    else
        error "Failed to authenticate with Vault"
        return 1
    fi

    # Enable KV secrets engine if not already enabled
    log "Checking if KV secrets engine is enabled..."
    if ! oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets list | grep -q "^secret/"; then
        log "Enabling KV secrets engine at secret/ path..."
        if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault secrets enable -path=secret kv-v2; then
            success "KV secrets engine enabled successfully"
        else
            error "Failed to enable KV secrets engine"
            return 1
        fi
    else
        success "KV secrets engine already enabled"
    fi

    return 0
}

# Function to add base domain configuration
add_base_domain() {
    local environment="${1:-dev}"
    log "Adding base domain configuration for environment: $environment"

    # Check if base domain already exists
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/config/$environment &>/dev/null; then
        warn "Base domain configuration for $environment already exists in Vault"
        read -p "Do you want to update it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping base domain configuration update"
            return 0
        fi
    fi

    echo
    echo "Please provide the base domain for $environment environment."
    echo "Examples: sandbox1936.opentlc.com, sandbox3223.opentlc.com, your-domain.com"
    echo
    read -p "Enter base domain for $environment (default: sandbox3223.opentlc.com): " -r BASE_DOMAIN

    # Use default if empty
    if [[ -z "$BASE_DOMAIN" ]]; then
        BASE_DOMAIN="sandbox3223.opentlc.com"
    fi

    log "Using base domain: $BASE_DOMAIN for environment: $environment"

    # Add to Vault
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put secret/openshift/config/$environment base_domain="$BASE_DOMAIN"; then
        success "Base domain configuration added to Vault successfully"
        log "Environment: $environment -> Base Domain: $BASE_DOMAIN"
    else
        error "Failed to add base domain configuration to Vault"
        return 1
    fi
}

# Function to add pull secret
add_pull_secret() {
    log "Adding OpenShift pull secret to Vault..."

    # Check if pull secret already exists
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/pull-secret &>/dev/null; then
        warn "Pull secret already exists in Vault"
        read -p "Do you want to update it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping pull secret update"
            return 0
        fi
    fi

    # Look for pull secret file
    local pull_secret_file="$HOME/pull-secret.json"

    if [[ ! -f "$pull_secret_file" ]]; then
        error "Pull secret file not found at: $pull_secret_file"
        echo
        echo "Please download your pull secret from: https://console.redhat.com/openshift/install/pull-secret"
        echo "And save it as: $pull_secret_file"
        return 1
    fi

    log "Reading pull secret from: $pull_secret_file"

    # Read and validate pull secret
    local PULL_SECRET
    if ! PULL_SECRET=$(cat "$pull_secret_file"); then
        error "Failed to read pull secret file"
        return 1
    fi

    if [[ -z "$PULL_SECRET" ]]; then
        error "Pull secret file is empty"
        return 1
    fi

    # Validate JSON format
    if ! echo "$PULL_SECRET" | jq . &>/dev/null; then
        error "Invalid JSON format in pull secret file"
        return 1
    fi

    log "Pull secret file validated successfully"

    # Add to Vault
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put secret/openshift/pull-secret pullSecret="$PULL_SECRET"; then
        success "Pull secret added to Vault successfully"
    else
        error "Failed to add pull secret to Vault"
        return 1
    fi
}

# Function to generate and add SSH keys
add_ssh_keys() {
    local environment="${1:-dev}"
    log "Adding SSH keys for environment: $environment"
    
    # Check if SSH keys already exist
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/ssh-keys/$environment &>/dev/null; then
        warn "SSH keys for $environment already exist in Vault"
        read -p "Do you want to regenerate them? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Skipping SSH key generation"
            return 0
        fi
    fi
    
    # Generate SSH key pair
    local temp_dir=$(mktemp -d)
    local private_key_file="$temp_dir/id_rsa"
    local public_key_file="$temp_dir/id_rsa.pub"
    
    log "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$private_key_file" -N "" -C "openshift-$environment-$(date +%Y%m%d)"
    
    if [[ ! -f "$private_key_file" || ! -f "$public_key_file" ]]; then
        error "Failed to generate SSH keys"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Read keys
    local private_key=$(cat "$private_key_file")
    local public_key=$(cat "$public_key_file")
    
    # Add to Vault
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv put secret/openshift/ssh-keys/$environment private_key="$private_key" public_key="$public_key"; then
        success "SSH keys for $environment added to Vault successfully"
        log "Public key: $public_key"
    else
        error "Failed to add SSH keys to Vault"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
}

# Function to verify secrets
verify_secrets() {
    log "Verifying secrets in Vault..."
    
    local all_good=true
    
    # Check pull secret
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/pull-secret &>/dev/null; then
        success "✅ Pull secret exists"
    else
        error "❌ Pull secret missing"
        all_good=false
    fi

    # Check SSH keys for dev environment
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/ssh-keys/dev &>/dev/null; then
        success "✅ SSH keys for dev environment exist"
    else
        error "❌ SSH keys for dev environment missing"
        all_good=false
    fi

    # Check base domain configuration for dev environment
    if oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get secret/openshift/config/dev &>/dev/null; then
        success "✅ Base domain configuration for dev environment exists"
        # Show the configured domain
        local configured_domain=$(oc exec $VAULT_POD -n $VAULT_NAMESPACE -- env VAULT_TOKEN="$ROOT_TOKEN" vault kv get -field=base_domain secret/openshift/config/dev 2>/dev/null || echo "unknown")
        log "   Configured domain: $configured_domain"
    else
        error "❌ Base domain configuration for dev environment missing"
        all_good=false
    fi
    
    if $all_good; then
        success "All required secrets are present in Vault!"
        return 0
    else
        error "Some secrets are missing. Please add them before running deployments."
        return 1
    fi
}

# Main execution
main() {
    log "Starting OpenShift secrets setup for Vault..."
    
    # Check Vault status
    if ! check_vault_status; then
        exit 1
    fi
    
    # Add secrets
    add_pull_secret
    add_ssh_keys "dev"
    add_base_domain "dev"
    
    # Verify all secrets
    verify_secrets
    
    success "OpenShift secrets setup completed!"
    log "You can now run the multi-cloud deployment workflow."
}

# Run main function
main "$@"
