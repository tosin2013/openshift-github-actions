#!/bin/bash
#
# deploy_vault_ha_tls_complete.sh
#
# Complete end-to-end script for deploying Vault HA with TLS certificates managed by cert-manager
# This script orchestrates the entire deployment process:
# 1. Deploys Vault with TLS configuration
# 2. Applies cert-manager resources
# 3. Initializes and unseals Vault
#
# Author: Tosin Akinosho
# Date: June 2025

set -e

# Text colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log function
log() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${GREEN}[${timestamp}] [INFO] $1${NC}"
}

error() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${RED}[${timestamp}] [ERROR] $1${NC}" >&2
}

warn() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo -e "${YELLOW}[${timestamp}] [WARN] $1${NC}"
}

# Configuration
# Get OpenShift cluster domain from route
OPENSHIFT_DOMAIN=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null | sed 's/console-openshift-console\.//g' || echo "apps.cluster-67wft.67wft.sandbox1936.opentlc.com")

# Default namespace for Vault deployment
export VAULT_NAMESPACE=${VAULT_NAMESPACE:-"vault-test-pragmatic"}

# Export domain for other scripts to use
export VAULT_DOMAIN=${VAULT_DOMAIN:-$OPENSHIFT_DOMAIN}

# Check if required scripts exist
check_prerequisites() {
  log "Checking prerequisites..."
  
  local required_scripts=("deploy_vault_with_tls.sh" "direct_vault_init.sh")
  local required_templates=("ansible/roles/openshift_prereqs/templates/vault-issuer.yaml.j2" "ansible/roles/openshift_prereqs/templates/vault-certificate.yaml.j2")
  
  for script in "${required_scripts[@]}"; do
    if [[ ! -f "$script" ]]; then
      error "Required script not found: $script"
      exit 1
    fi
    
    # Make sure scripts are executable
    chmod +x "$script"
  done
  
  for template in "${required_templates[@]}"; do
    if [[ ! -f "$template" ]]; then
      error "Required template not found: $template"
      exit 1
    fi
  done
  
  # Check if cert-manager is installed in the cluster
  log "Checking if cert-manager is installed..."
  if ! oc get crd certificates.cert-manager.io &>/dev/null; then
    error "cert-manager is not installed in the cluster. Please install cert-manager first."
    exit 1
  fi
  
  log "All prerequisites satisfied."
}

# Create namespace and TLS resources first
create_namespace_and_tls() {
  log "Step 1/3: Creating namespace and TLS certificate..."

  # Create namespace if it doesn't exist
  if ! oc get namespace "$VAULT_NAMESPACE" &>/dev/null; then
    oc create namespace "$VAULT_NAMESPACE"
    log "Created namespace: $VAULT_NAMESPACE"
  else
    log "Namespace $VAULT_NAMESPACE already exists"
  fi

  # Switch to the namespace
  oc project "$VAULT_NAMESPACE"

  # Render cert-manager templates first
  log "Rendering cert-manager templates..."

  # Check if Python virtual environment exists
  if [[ ! -d "venv" ]]; then
    log "Creating Python virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    pip install jinja2
    deactivate
  fi

  # Activate virtual environment and render templates
  source venv/bin/activate

  # Set environment variables for template rendering
  export vault_namespace="$VAULT_NAMESPACE"
  export vault_domain="${VAULT_DOMAIN:-apps.cluster-67wft.67wft.sandbox1936.opentlc.com}"

  # Create output directory
  mkdir -p rendered_templates

  # Render issuer template
  python scripts/render_template.py ansible/roles/openshift_prereqs/templates/vault-issuer.yaml.j2 rendered_templates/vault-issuer.yaml

  # Render certificate template
  python scripts/render_template.py ansible/roles/openshift_prereqs/templates/vault-certificate.yaml.j2 rendered_templates/vault-certificate.yaml

  deactivate

  # Apply cert-manager resources
  log "Applying cert-manager issuer..."
  oc apply -f rendered_templates/vault-issuer.yaml -n $VAULT_NAMESPACE

  log "Applying cert-manager certificate..."
  oc apply -f rendered_templates/vault-certificate.yaml -n $VAULT_NAMESPACE

  # Wait for certificate to be issued
  log "Waiting for certificate to be issued..."
  local max_attempts=30
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    local cert_ready=$(oc get certificate vault-tls -n $VAULT_NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [[ "$cert_ready" == "True" ]]; then
      log "Certificate issued successfully!"
      break
    fi

    attempt=$((attempt + 1))
    log "Waiting for certificate to be ready ($attempt/$max_attempts)..."
    sleep 10
  done

  if [[ $attempt -eq $max_attempts ]]; then
    error "Timeout waiting for certificate to be issued."
    exit 1
  fi

  # Verify TLS secret exists
  if oc get secret vault-tls -n $VAULT_NAMESPACE &>/dev/null; then
    log "✅ TLS secret 'vault-tls' is ready for Vault deployment"
  else
    error "TLS secret 'vault-tls' was not created"
    exit 1
  fi
}

# Deploy Vault with TLS configuration
deploy_vault() {
  log "Step 2/3: Deploying Vault with TLS configuration..."

  # First deploy Vault WITHOUT TLS to get pods running
  log "Phase 1: Deploying Vault without TLS (to avoid secret dependency)..."
  deploy_vault_without_tls

  # Then upgrade to enable TLS
  log "Phase 2: Upgrading Vault to enable TLS..."
  upgrade_vault_with_tls

  # Fix TLS ConfigMap issue (Helm doesn't properly apply TLS config)
  fix_tls_configmap
}

# Deploy Vault without TLS first
deploy_vault_without_tls() {
  log "Deploying Vault without TLS to avoid secret dependency..."

  # CRITICAL: Create service account and SCC first
  log "Creating service account and SCC..."

  # Activate virtual environment
  source venv/bin/activate

  # Set required environment variables for SCC and SA templates
  export vault_namespace="$VAULT_NAMESPACE"
  export vault_scc_name="vault-scc"
  export vault_service_account_name="vault"

  # Render and apply SCC
  python scripts/render_template.py ansible/roles/openshift_prereqs/templates/vault-scc.yaml.j2 rendered_templates/vault-scc.yaml
  oc apply -f rendered_templates/vault-scc.yaml

  # Render and apply service account
  python scripts/render_template.py ansible/roles/openshift_prereqs/templates/vault-sa.yaml.j2 rendered_templates/vault-sa.yaml
  oc apply -f rendered_templates/vault-sa.yaml -n "$VAULT_NAMESPACE"

  # Add SCC to service account
  oc adm policy add-scc-to-user vault-scc -z vault -n "$VAULT_NAMESPACE"

  # Set environment variables for template rendering (TLS disabled)
  export vault_namespace="$VAULT_NAMESPACE"
  export vault_helm_image_repository="hashicorp/vault"
  export vault_image_tag="1.15.6"
  export vault_helm_image_pull_policy="IfNotPresent"
  export vault_scc_name="vault-scc"
  export vault_auto_unseal_enabled="false"
  export vault_ha_enabled="true"
  export vault_replicas="3"
  export vault_ui_enabled="true"
  export vault_route_enabled="true"
  export vault_pvc_size="10Gi"
  export vault_storage_class="gp3-csi"
  export vault_audit_storage_enabled="false"
  export vault_csi_enabled="false"
  export vault_injector_enabled="false"
  export vault_tls_enabled="false"  # KEY: Disable TLS initially

  # Render template without TLS
  python scripts/render_template.py ansible/roles/vault_helm_deploy/templates/vault-values.yaml.j2 rendered_templates/vault-values-no-tls.yaml

  # Deploy Vault without TLS
  helm upgrade --install vault hashicorp/vault \
    --namespace "$VAULT_NAMESPACE" \
    --version "0.28.0" \
    --values rendered_templates/vault-values-no-tls.yaml

  deactivate

  # Wait for pods to be running
  log "Waiting for Vault pods to be running (without TLS)..."
  local max_attempts=20
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    # Use a more reliable method to count pods
    local running_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' \n')
    local total_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l | tr -d ' \n')

    # Ensure variables are clean integers
    running_pods=$(echo "$running_pods" | sed 's/[^0-9]//g')
    total_pods=$(echo "$total_pods" | sed 's/[^0-9]//g')
    running_pods=${running_pods:-0}
    total_pods=${total_pods:-0}

    log "Pod status: $running_pods/$total_pods running"

    if [[ $running_pods -eq $total_pods && $total_pods -gt 0 ]]; then
      log "✅ All Vault pods are running without TLS."
      return 0
    fi

    attempt=$((attempt + 1))
    log "Waiting for Vault pods to be running ($attempt/$max_attempts)..."
    sleep 15
  done

  error "Timeout waiting for Vault pods to be running without TLS."
  exit 1
}

# Upgrade Vault to enable TLS
upgrade_vault_with_tls() {
  log "Upgrading Vault to enable TLS..."

  # Activate virtual environment
  source venv/bin/activate

  # Set environment variables for template rendering (TLS enabled)
  export vault_tls_enabled="true"  # KEY: Enable TLS now

  # Render template with TLS
  python scripts/render_template.py ansible/roles/vault_helm_deploy/templates/vault-values.yaml.j2 rendered_templates/vault-values-with-tls.yaml

  # Upgrade Vault with TLS
  helm upgrade vault hashicorp/vault \
    --namespace "$VAULT_NAMESPACE" \
    --version "0.28.0" \
    --values rendered_templates/vault-values-with-tls.yaml

  deactivate

  # Wait for pods to restart with TLS
  log "Waiting for Vault pods to restart with TLS..."
  local max_attempts=20
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    # Use a more reliable method to count pods
    local running_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' \n')
    local total_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l | tr -d ' \n')

    # Ensure variables are clean integers
    running_pods=$(echo "$running_pods" | sed 's/[^0-9]//g')
    total_pods=$(echo "$total_pods" | sed 's/[^0-9]//g')
    running_pods=${running_pods:-0}
    total_pods=${total_pods:-0}

    log "Pod status: $running_pods/$total_pods running"

    if [[ $running_pods -eq $total_pods && $total_pods -gt 0 ]]; then
      log "✅ All Vault pods are running with TLS enabled."
      return 0
    fi

    attempt=$((attempt + 1))
    log "Waiting for Vault pods to restart with TLS ($attempt/$max_attempts)..."
    sleep 15
  done

  error "Timeout waiting for Vault pods to restart with TLS."
  exit 1
}

# Fix TLS ConfigMap issue - Helm doesn't properly apply TLS configuration
fix_tls_configmap() {
  log "Step 2.5: Fixing TLS ConfigMap configuration..."

  # Check if ConfigMap has the wrong TLS configuration
  local tls_disabled=$(oc get configmap vault-config -n $VAULT_NAMESPACE -o yaml | grep "tls_disable = 1" || echo "")

  if [[ -n "$tls_disabled" ]]; then
    log "Detected TLS disabled in ConfigMap. Applying proven TLS fix..."

    # Apply the proven TLS configuration patch
    oc patch configmap vault-config -n $VAULT_NAMESPACE --patch '{
      "data": {
        "extraconfig-from-values.hcl": "disable_mlock = true\nui = true\n\nlistener \"tcp\" {\n  address = \"[::]:8200\"\n  cluster_address = \"[::]:8201\"\n  tls_cert_file = \"/vault/userconfig/vault-tls/tls.crt\"\n  tls_key_file = \"/vault/userconfig/vault-tls/tls.key\"\n  tls_client_ca_file = \"/vault/userconfig/vault-tls/ca.crt\"\n  tls_disable = false\n}\n\nstorage \"raft\" {\n  path = \"/vault/data\"\n  retry_join {\n    leader_api_addr = \"https://vault-0.vault-internal:8200\"\n    leader_ca_cert_file = \"/vault/userconfig/vault-tls/ca.crt\"\n    leader_client_cert_file = \"/vault/userconfig/vault-tls/tls.crt\"\n    leader_client_key_file = \"/vault/userconfig/vault-tls/tls.key\"\n  }\n}\n\nservice_registration \"kubernetes\" {}"
      }
    }'

    if [[ $? -eq 0 ]]; then
      log "✅ TLS ConfigMap patched successfully"

      # Restart pods to pick up the new TLS configuration
      log "Restarting Vault pods to apply TLS configuration..."
      oc delete pod vault-0 vault-1 vault-2 -n $VAULT_NAMESPACE

      # Wait for pods to restart with correct TLS config
      log "Waiting for Vault pods to restart with correct TLS configuration..."
      local max_attempts=20
      local attempt=0

      while [[ $attempt -lt $max_attempts ]]; do
        local running_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' \n')
        local total_pods=$(oc get pods -n $VAULT_NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | wc -l | tr -d ' \n')

        running_pods=$(echo "$running_pods" | sed 's/[^0-9]//g')
        total_pods=$(echo "$total_pods" | sed 's/[^0-9]//g')
        running_pods=${running_pods:-0}
        total_pods=${total_pods:-0}

        log "Pod status: $running_pods/$total_pods running"

        if [[ $running_pods -eq $total_pods && $total_pods -gt 0 ]]; then
          log "✅ All Vault pods restarted with correct TLS configuration"

          # Verify TLS is actually enabled by checking logs
          sleep 10
          local tls_status=$(oc logs vault-0 -n $VAULT_NAMESPACE | grep "Listener" | grep "tls.*enabled" || echo "")
          if [[ -n "$tls_status" ]]; then
            log "✅ TLS confirmed enabled in Vault logs"
          else
            warn "TLS status unclear from logs, but ConfigMap is correct"
          fi
          return 0
        fi

        attempt=$((attempt + 1))
        log "Waiting for pods to restart with TLS ($attempt/$max_attempts)..."
        sleep 15
      done

      error "Timeout waiting for Vault pods to restart with TLS configuration"
      exit 1
    else
      error "Failed to patch TLS ConfigMap"
      exit 1
    fi
  else
    log "✅ TLS ConfigMap already has correct configuration"
  fi
}

# Note: cert-manager resources are now handled in create_namespace_and_tls function

# Check and fix storage configuration
check_and_fix_storage() {
  log "Checking StatefulSet storage configuration..."

  # Check if StatefulSet has volumeClaimTemplates
  local volume_claims=$(oc get statefulset vault -n $VAULT_NAMESPACE -o jsonpath='{.spec.volumeClaimTemplates}' 2>/dev/null || echo "null")

  if [[ "$volume_claims" == "null" || "$volume_claims" == "[]" || -z "$volume_claims" ]]; then
    warn "StatefulSet has no persistent storage configured. Fixing with storage class..."

    # Re-render template with storage class
    log "Re-rendering Helm values with storage class..."
    if [[ -d "venv" ]]; then
      source venv/bin/activate

      # Set all required variables including storage class
      export vault_namespace="$VAULT_NAMESPACE"
      export vault_helm_image_repository="hashicorp/vault"
      export vault_image_tag="${VAULT_IMAGE_TAG:-1.15.6}"
      export vault_helm_image_pull_policy="IfNotPresent"
      export vault_scc_name="vault-scc"
      export vault_auto_unseal_enabled="false"
      export vault_ha_enabled="true"
      export vault_replicas="${VAULT_HA_REPLICAS:-3}"
      export vault_ui_enabled="true"
      export vault_route_enabled="true"
      export vault_pvc_size="10Gi"
      export vault_storage_class="gp3-csi"  # This is the key fix
      export vault_audit_storage_enabled="false"
      export vault_csi_enabled="false"
      export vault_injector_enabled="false"

      # Re-render the template
      python scripts/render_template.py ansible/roles/vault_helm_deploy/templates/vault-values.yaml.j2 rendered_templates/vault-values.yaml

      # Upgrade Helm deployment with corrected values
      log "Upgrading Helm deployment with persistent storage..."
      helm upgrade vault hashicorp/vault --namespace $VAULT_NAMESPACE --version 0.28.0 --values rendered_templates/vault-values.yaml

      deactivate
    else
      error "Python virtual environment not found. Cannot re-render template."
      exit 1
    fi
  else
    log "StatefulSet already has persistent storage configured."
  fi
}

# Initialize and unseal Vault
initialize_vault() {
  log "Step 3/3: Initializing and unsealing Vault..."
  
  # Wait a bit to ensure pods are fully ready
  sleep 10
  
  # Run the initialization script
  ./direct_vault_init.sh
  
  # Verify Vault is initialized and unsealed
  log "Verifying Vault initialization and unsealing..."
  
  # Set environment variables for Vault CLI
  export VAULT_ADDR=https://$(oc get route vault-ha -n $VAULT_NAMESPACE -o jsonpath='{.spec.host}'):443
  export VAULT_SKIP_VERIFY=true
  
  # Check if Vault is initialized and unsealed
  local vault_status=$(vault status -format=json 2>/dev/null || echo '{"initialized": false, "sealed": true}')
  local initialized=$(echo "$vault_status" | grep -o '"initialized":[^,}]*' | cut -d ':' -f2 | tr -d ' "')
  local sealed=$(echo "$vault_status" | grep -o '"sealed":[^,}]*' | cut -d ':' -f2 | tr -d ' "')
  
  # Print the full status for debugging
  log "Vault status: $vault_status"
  
  if [[ "$initialized" == "true" && "$sealed" == "false" ]]; then
    log "Vault is successfully initialized and unsealed."
  else
    warn "Vault initialization status: initialized=$initialized, sealed=$sealed"
    warn "Vault may not be fully initialized and unsealed. Please check the logs and status."
  fi
}

# Display final information
display_info() {
  log "Deployment complete!"
  log "To access Vault, use the following commands:"
  echo ""
  echo "export VAULT_ADDR=https://$(oc get route vault-ha -n $VAULT_NAMESPACE -o jsonpath='{.spec.host}'):443"
  echo "export VAULT_SKIP_VERIFY=true"
  echo "vault status"
  echo ""
  log "For more information, see VAULT-TLS-CERT-MANAGER.md"
}

# Main function
main() {
  log "Starting complete Vault HA deployment with TLS managed by cert-manager..."

  check_prerequisites

  # Step 1: Create namespace and apply cert-manager resources FIRST
  create_namespace_and_tls

  # Step 2: Deploy Vault with TLS (now that secret exists)
  deploy_vault

  # Step 3: Initialize and unseal Vault
  initialize_vault
  display_info

  log "All steps completed successfully!"
}

# Run the main function
main
