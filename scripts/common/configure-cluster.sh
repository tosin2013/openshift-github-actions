#!/bin/bash

# Configure OpenShift cluster post-installation
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
ENVIRONMENT="dev"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Configure OpenShift cluster after installation.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --environment ENV           Environment (dev, staging, production)
  --help                      Show this help message

EXAMPLES:
  # Configure AWS cluster
  $0 --provider aws --cluster-name my-cluster --environment dev

  # Configure production cluster
  $0 --provider azure --cluster-name prod-cluster --environment production

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
    --environment)
      ENVIRONMENT="$2"
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
if [ -z "$PROVIDER" ] || [ -z "$CLUSTER_NAME" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Check if oc command is available
if ! command_exists oc; then
  log "ERROR" "OpenShift CLI (oc) is not installed or not in PATH"
  exit 1
fi

# Check if KUBECONFIG is set
if [ -z "${KUBECONFIG:-}" ]; then
  log "ERROR" "KUBECONFIG environment variable is not set"
  exit 1
fi

# Wait for cluster to be ready
wait_for_cluster_ready() {
  log "INFO" "Waiting for cluster to be ready"
  
  wait_for "oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}' | grep -q True" 600 30 "cluster version to be available"
  wait_for "oc get nodes --no-headers | grep -v NotReady | wc -l | grep -q -v '^0$'" 600 30 "nodes to be ready"
  
  log "INFO" "Cluster is ready for configuration"
}

# Configure cluster monitoring
configure_monitoring() {
  log "INFO" "Configuring cluster monitoring"
  
  # Create monitoring configuration
  cat << EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    prometheusK8s:
      retention: 7d
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 50Gi
    alertmanagerMain:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 10Gi
EOF
  
  log "INFO" "Cluster monitoring configured"
}

# Configure image registry
configure_image_registry() {
  log "INFO" "Configuring image registry"
  
  case "$PROVIDER" in
    aws)
      # For AWS, use S3 for registry storage
      oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"s3":{"bucket":"'$CLUSTER_NAME'-registry","region":"'${AWS_DEFAULT_REGION:-us-east-1}'"}},"replicas":2}}'
      ;;
    azure)
      # For Azure, use Azure Blob Storage
      oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"azure":{"accountName":"'$CLUSTER_NAME'registry","container":"registry"}},"replicas":2}}'
      ;;
    gcp)
      # For GCP, use Google Cloud Storage
      oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"gcs":{"bucket":"'$CLUSTER_NAME'-registry"}},"replicas":2}}'
      ;;
    *)
      # Fallback to emptyDir for unsupported providers
      log "WARN" "Using emptyDir storage for image registry (not recommended for production)"
      oc patch configs.imageregistry.operator.openshift.io cluster --type merge --patch '{"spec":{"managementState":"Managed","storage":{"emptyDir":{}},"replicas":1}}'
      ;;
  esac
  
  log "INFO" "Image registry configured"
}

# Configure ingress
configure_ingress() {
  log "INFO" "Configuring ingress"
  
  # Set ingress controller replicas based on environment
  local replicas=2
  if [ "$ENVIRONMENT" = "dev" ]; then
    replicas=1
  elif [ "$ENVIRONMENT" = "production" ]; then
    replicas=3
  fi
  
  oc patch ingresscontroller default -n openshift-ingress-operator --type merge --patch '{"spec":{"replicas":'$replicas'}}'
  
  log "INFO" "Ingress configured with $replicas replicas"
}

# Configure authentication
configure_authentication() {
  log "INFO" "Configuring authentication"
  
  # This is a placeholder for authentication configuration
  # In a real environment, you would configure LDAP, OIDC, or other identity providers
  
  log "INFO" "Authentication configuration completed (using default kubeadmin)"
}

# Configure RBAC
configure_rbac() {
  log "INFO" "Configuring RBAC"
  
  # Create environment-specific namespaces
  local namespaces=("$ENVIRONMENT-apps" "$ENVIRONMENT-data" "$ENVIRONMENT-monitoring")
  
  for namespace in "${namespaces[@]}"; do
    oc create namespace "$namespace" --dry-run=client -o yaml | oc apply -f -
    oc label namespace "$namespace" environment="$ENVIRONMENT"
    oc label namespace "$namespace" managed-by="openshift-automation"
  done
  
  # Create basic RBAC for environment
  cat << EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $ENVIRONMENT-developer
rules:
- apiGroups: [""]
  resources: ["pods", "services", "configmaps", "secrets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: $ENVIRONMENT-developers
  namespace: $ENVIRONMENT-apps
subjects:
- kind: Group
  name: $ENVIRONMENT-developers
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: $ENVIRONMENT-developer
  apiGroup: rbac.authorization.k8s.io
EOF
  
  log "INFO" "RBAC configured for environment: $ENVIRONMENT"
}

# Configure network policies
configure_network_policies() {
  log "INFO" "Configuring network policies"
  
  # Create default deny-all network policy for environment namespaces
  local namespaces=("$ENVIRONMENT-apps" "$ENVIRONMENT-data")
  
  for namespace in "${namespaces[@]}"; do
    cat << EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: $namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
  namespace: $namespace
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: $namespace
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: $namespace
EOF
  done
  
  log "INFO" "Network policies configured"
}

# Configure resource quotas
configure_resource_quotas() {
  log "INFO" "Configuring resource quotas"
  
  # Set quotas based on environment
  local cpu_limit="4"
  local memory_limit="8Gi"
  local storage_limit="50Gi"
  
  if [ "$ENVIRONMENT" = "production" ]; then
    cpu_limit="16"
    memory_limit="32Gi"
    storage_limit="200Gi"
  elif [ "$ENVIRONMENT" = "staging" ]; then
    cpu_limit="8"
    memory_limit="16Gi"
    storage_limit="100Gi"
  fi
  
  local namespaces=("$ENVIRONMENT-apps" "$ENVIRONMENT-data")
  
  for namespace in "${namespaces[@]}"; do
    cat << EOF | oc apply -f -
apiVersion: v1
kind: ResourceQuota
metadata:
  name: compute-quota
  namespace: $namespace
spec:
  hard:
    requests.cpu: "$cpu_limit"
    requests.memory: "$memory_limit"
    limits.cpu: "$((cpu_limit * 2))"
    limits.memory: "$((memory_limit * 2))"
    persistentvolumeclaims: "10"
    requests.storage: "$storage_limit"
EOF
  done
  
  log "INFO" "Resource quotas configured"
}

# Configure cluster autoscaler (if supported)
configure_autoscaler() {
  log "INFO" "Configuring cluster autoscaler"
  
  # Only configure autoscaler for cloud providers that support it
  case "$PROVIDER" in
    aws|azure|gcp)
      cat << EOF | oc apply -f -
apiVersion: autoscaling.openshift.io/v1
kind: ClusterAutoscaler
metadata:
  name: default
spec:
  podPriorityThreshold: -10
  resourceLimits:
    maxNodesTotal: 20
    cores:
      min: 8
      max: 128
    memory:
      min: 4
      max: 256
  scaleDown:
    enabled: true
    delayAfterAdd: 10m
    delayAfterDelete: 10s
    delayAfterFailure: 30s
    unneededTime: 10m
EOF
      log "INFO" "Cluster autoscaler configured"
      ;;
    *)
      log "INFO" "Cluster autoscaler not supported for provider: $PROVIDER"
      ;;
  esac
}

# Main configuration function
main() {
  log "INFO" "Starting cluster configuration"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Environment: $ENVIRONMENT"
  
  # Wait for cluster to be ready
  wait_for_cluster_ready
  
  # Run configuration steps
  configure_monitoring
  configure_image_registry
  configure_ingress
  configure_authentication
  configure_rbac
  configure_network_policies
  configure_resource_quotas
  configure_autoscaler
  
  log "INFO" "Cluster configuration completed successfully"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## Cluster Configuration Completed"
    add_to_step_summary "✅ Successfully configured cluster"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Environment**: $ENVIRONMENT"
    add_to_step_summary ""
    add_to_step_summary "**Configured Components:**"
    add_to_step_summary "- Monitoring and alerting"
    add_to_step_summary "- Image registry"
    add_to_step_summary "- Ingress controller"
    add_to_step_summary "- RBAC and namespaces"
    add_to_step_summary "- Network policies"
    add_to_step_summary "- Resource quotas"
    add_to_step_summary "- Cluster autoscaler (if supported)"
  fi
  
  return 0
}

# Run main function
main "$@"
