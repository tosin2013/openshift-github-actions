#!/bin/bash

# Script to apply cert-manager resources for Vault HA TLS certificates
# This script creates a self-signed issuer and certificate with proper SANs
# for Vault HA pod-to-pod communication

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log with timestamp
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

# Namespace where Vault is deployed
NAMESPACE=${VAULT_NAMESPACE:-"vault-test-pragmatic"}

# Get OpenShift cluster domain if not provided
if [ -z "${VAULT_DOMAIN}" ]; then
  DOMAIN=$(oc get route console -n openshift-console -o jsonpath='{.spec.host}' 2>/dev/null | sed 's/console-openshift-console\.//g' || echo "apps.cluster-67wft.67wft.sandbox1936.opentlc.com")
else
  DOMAIN="${VAULT_DOMAIN}"
fi

log "INFO" "Using OpenShift domain: $DOMAIN"

# Export environment variables for template substitution
export NAMESPACE="$NAMESPACE"
export DOMAIN="$DOMAIN"

# Check if cert-manager is installed
check_cert_manager() {
  log "INFO" "Checking if cert-manager is installed..."
  if ! oc get crd certificates.cert-manager.io &>/dev/null; then
    log "ERROR" "cert-manager CRDs not found. Please install cert-manager first."
    exit 1
  fi
  log "INFO" "cert-manager is installed."
}

# Generate YAML files from templates
generate_yaml_files() {
  log "INFO" "Generating YAML files from templates..."
  
  # Check if template files exist
  if [[ ! -f "vault-issuer.template.yaml" ]]; then
    log "ERROR" "Template file vault-issuer.template.yaml not found"
    exit 1
  fi
  
  if [[ ! -f "vault-certificate.template.yaml" ]]; then
    log "ERROR" "Template file vault-certificate.template.yaml not found"
    exit 1
  fi
  
  # Generate issuer YAML
  log "INFO" "Generating issuer YAML file"
  envsubst < vault-issuer.template.yaml > vault-issuer.yaml
  
  # Generate certificate YAML
  log "INFO" "Generating certificate YAML file"
  envsubst < vault-certificate.template.yaml > vault-certificate.yaml
}

# Apply the self-signed issuer
apply_issuer() {
  log "INFO" "Applying self-signed issuer..."
  oc apply -f vault-issuer.yaml
  
  # Wait for issuer to be ready
  log "INFO" "Waiting for issuer to be ready..."
  
  # Wait for the issuer to be ready
  local retries=0
  local max_retries=10
  
  while [[ $retries -lt $max_retries ]]; do
    if oc get issuer vault-selfsigned-issuer -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      log "INFO" "Issuer is ready."
      return 0
    fi
    
    retries=$((retries + 1))
    log "DEBUG" "Waiting for issuer to be ready (attempt $retries/$max_retries)..."
    sleep 5
  done
  
  log "ERROR" "Issuer did not become ready within the expected time."
  return 1
}

# Apply the certificate
apply_certificate() {
  log "INFO" "Applying certificate with proper SANs for Vault HA..."
  oc apply -f vault-certificate.yaml
  log "INFO" "Waiting for certificate to be issued..."
  
  # Wait for the certificate to be issued
  local retries=0
  local max_retries=20
  
  while [[ $retries -lt $max_retries ]]; do
    if oc get certificate vault-tls -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"; then
      log "INFO" "Certificate has been issued successfully."
      return 0
    fi
    
    retries=$((retries + 1))
    log "DEBUG" "Waiting for certificate to be issued (attempt $retries/$max_retries)..."
    sleep 5
  done
  
  log "ERROR" "Certificate was not issued within the expected time."
  return 1
}

# Verify the secret has been created
verify_secret() {
  log "INFO" "Verifying TLS secret..."
  if ! oc get secret vault-tls -n $NAMESPACE &>/dev/null; then
    log "ERROR" "TLS secret 'vault-tls' not found."
    return 1
  fi
  
  # Check if the secret contains the required keys
  if oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data}' | grep -q "tls.crt" && \
     oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data}' | grep -q "tls.key"; then
    log "INFO" "TLS secret contains the required keys (tls.crt and tls.key)."
    return 0
  else
    log "ERROR" "TLS secret does not contain the required keys."
    return 1
  fi
}

# Restart Vault pods to pick up the new certificates
restart_vault_pods() {
  log "INFO" "Restarting Vault pods to pick up the new certificates..."
  
  # Scale down the StatefulSet
  oc scale statefulset vault --replicas=0 -n $NAMESPACE
  log "INFO" "Scaled down Vault StatefulSet to 0 replicas."

  # Wait for pods to terminate
  log "INFO" "Waiting for Vault pods to terminate..."
  while oc get pods -n $NAMESPACE -l app.kubernetes.io/name=vault --no-headers 2>/dev/null | grep -q "vault-"; do
    log "DEBUG" "Waiting for Vault pods to terminate..."
    sleep 5
  done

  # Scale up the StatefulSet
  oc scale statefulset vault --replicas=3 -n $NAMESPACE
  log "INFO" "Scaled up Vault StatefulSet to 3 replicas."
  
  # Wait for pods to be ready
  log "INFO" "Waiting for Vault pods to become ready..."
  local retries=0
  local max_retries=30
  
  while [[ $retries -lt $max_retries ]]; do
    if [[ $(oc get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].status.containerStatuses[0].ready}' | tr ' ' '\n' | grep -c "true") -eq 3 ]]; then
      log "INFO" "All Vault pods are ready."
      return 0
    fi
    
    retries=$((retries + 1))
    log "DEBUG" "Waiting for Vault pods to become ready (attempt $retries/$max_retries)..."
    sleep 10
  done
  
  log "WARN" "Not all Vault pods became ready within the expected time. You may need to initialize and unseal them."
  return 0
}

# Main function
# Verify that the TLS secret was created correctly
verify_tls_secret() {
  log "INFO" "Verifying TLS secret was created correctly..."
  
  # Check if the secret exists
  if ! oc get secret vault-tls -n $NAMESPACE &>/dev/null; then
    log "ERROR" "TLS secret vault-tls not found"
    exit 1
  fi
  
  # Check if the secret has the required keys
  if ! oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' &>/dev/null || \
     ! oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data.tls\.key}' &>/dev/null; then
    log "ERROR" "TLS secret vault-tls does not have the required keys (tls.crt and tls.key)"
    exit 1
  fi
  
  log "INFO" "TLS secret verified successfully"

  # Additional security validation
  log "INFO" "Performing additional certificate validation..."

  # Check certificate validity period
  local cert_not_after
  cert_not_after=$(oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "Unknown")
  log "INFO" "Certificate expires: $cert_not_after"

  # Check certificate SANs
  local cert_sans
  cert_sans=$(oc get secret vault-tls -n $NAMESPACE -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 || echo "No SANs found")
  log "INFO" "Certificate SANs: $cert_sans"
}

# Function to validate TLS configuration consistency
validate_tls_consistency() {
  log "INFO" "Validating TLS configuration consistency across all pods..."

  local consistent=true
  for pod in vault-0 vault-1 vault-2; do
    if oc get pod "$pod" -n "$NAMESPACE" >/dev/null 2>&1; then
      log "INFO" "Checking TLS configuration for $pod..."

      # Check if TLS secret is mounted
      if ! oc exec "$pod" -n "$NAMESPACE" -- ls /vault/userconfig/vault-tls/tls.crt >/dev/null 2>&1; then
        log "ERROR" "TLS certificate not found in $pod"
        consistent=false
      fi

      # Check if TLS secret is mounted
      if ! oc exec "$pod" -n "$NAMESPACE" -- ls /vault/userconfig/vault-tls/tls.key >/dev/null 2>&1; then
        log "ERROR" "TLS private key not found in $pod"
        consistent=false
      fi
    fi
  done

  if [ "$consistent" = true ]; then
    log "INFO" "✅ TLS configuration is consistent across all pods"
  else
    log "ERROR" "❌ TLS configuration inconsistency detected"
    return 1
  fi
}

main() {
  log "INFO" "Starting Vault TLS certificate management with cert-manager..."
  check_cert_manager
  generate_yaml_files
  apply_issuer
  apply_certificate
  verify_tls_secret
  restart_vault_pods
  validate_tls_consistency

  log "INFO" "✅ TLS certificate management completed successfully."
  log "INFO" "Next steps:"
  log "INFO" "1. Run: ./direct_vault_init.sh (if Vault needs initialization)"
  log "INFO" "2. Run: ./verify_vault_deployment.sh (to verify deployment)"
  log "INFO" "3. Test external access: https://vault-$NAMESPACE.$DOMAIN"
}

# Run the main function
main "$@"
