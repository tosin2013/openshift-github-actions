#!/bin/bash

# Validate OpenShift cluster deployment
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../scripts/common/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
TIMEOUT=1800  # 30 minutes
CHECK_INTERVAL=30

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Validate OpenShift cluster deployment and health.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --timeout SECONDS           Timeout for validation (default: 1800)
  --check-interval SECONDS    Check interval (default: 30)
  --help                      Show this help message

EXAMPLES:
  # Validate AWS cluster
  $0 --provider aws --cluster-name my-cluster

  # Validate with custom timeout
  $0 --provider azure --cluster-name my-cluster --timeout 3600

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
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --check-interval)
      CHECK_INTERVAL="$2"
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

# Validate cluster connectivity
validate_cluster_connectivity() {
  log "INFO" "Validating cluster connectivity"
  
  if ! oc whoami >/dev/null 2>&1; then
    log "ERROR" "Cannot connect to cluster. Check KUBECONFIG and cluster status."
    return 1
  fi
  
  local cluster_name=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}' 2>/dev/null || echo "unknown")
  log "INFO" "Connected to cluster: $cluster_name"
  
  return 0
}

# Check cluster version
check_cluster_version() {
  log "INFO" "Checking cluster version"
  
  local version=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null || echo "unknown")
  local available=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "unknown")
  local progressing=$(oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Progressing")].status}' 2>/dev/null || echo "unknown")
  
  log "INFO" "Cluster version: $version"
  log "INFO" "Available: $available"
  log "INFO" "Progressing: $progressing"
  
  if [ "$available" != "True" ]; then
    log "WARN" "Cluster is not fully available yet"
    return 1
  fi
  
  return 0
}

# Check node status
check_node_status() {
  log "INFO" "Checking node status"
  
  local total_nodes=$(oc get nodes --no-headers | wc -l)
  local ready_nodes=$(oc get nodes --no-headers | grep -c " Ready " || echo "0")
  
  log "INFO" "Total nodes: $total_nodes"
  log "INFO" "Ready nodes: $ready_nodes"
  
  if [ "$ready_nodes" -eq 0 ]; then
    log "ERROR" "No nodes are ready"
    return 1
  fi
  
  if [ "$ready_nodes" -lt "$total_nodes" ]; then
    log "WARN" "Not all nodes are ready ($ready_nodes/$total_nodes)"
    oc get nodes
    return 1
  fi
  
  log "INFO" "All nodes are ready"
  return 0
}

# Check cluster operators
check_cluster_operators() {
  log "INFO" "Checking cluster operators"
  
  local total_operators=$(oc get clusteroperators --no-headers | wc -l)
  local available_operators=$(oc get clusteroperators --no-headers | grep -c "True.*False.*False" || echo "0")
  local degraded_operators=$(oc get clusteroperators --no-headers | grep -c ".*True.*True" || echo "0")
  
  log "INFO" "Total operators: $total_operators"
  log "INFO" "Available operators: $available_operators"
  log "INFO" "Degraded operators: $degraded_operators"
  
  if [ "$degraded_operators" -gt 0 ]; then
    log "WARN" "Some operators are degraded:"
    oc get clusteroperators | grep ".*True.*True"
  fi
  
  if [ "$available_operators" -lt "$total_operators" ]; then
    log "WARN" "Not all operators are available ($available_operators/$total_operators)"
    oc get clusteroperators | grep -v "True.*False.*False"
    return 1
  fi
  
  log "INFO" "All operators are available"
  return 0
}

# Check critical pods
check_critical_pods() {
  log "INFO" "Checking critical pods"
  
  local namespaces=("openshift-etcd" "openshift-kube-apiserver" "openshift-kube-controller-manager" "openshift-kube-scheduler")
  
  for namespace in "${namespaces[@]}"; do
    log "DEBUG" "Checking pods in namespace: $namespace"
    
    local total_pods=$(oc get pods -n "$namespace" --no-headers 2>/dev/null | wc -l || echo "0")
    local running_pods=$(oc get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    
    log "DEBUG" "Namespace $namespace: $running_pods/$total_pods pods running"
    
    if [ "$total_pods" -eq 0 ]; then
      log "WARN" "No pods found in namespace: $namespace"
      continue
    fi
    
    if [ "$running_pods" -lt "$total_pods" ]; then
      log "WARN" "Not all pods are running in namespace $namespace ($running_pods/$total_pods)"
      oc get pods -n "$namespace" | grep -v "Running"
    fi
  done
  
  return 0
}

# Check ingress
check_ingress() {
  log "INFO" "Checking ingress configuration"
  
  local ingress_available=$(oc get clusteroperator ingress -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "unknown")
  
  if [ "$ingress_available" != "True" ]; then
    log "WARN" "Ingress operator is not available"
    return 1
  fi
  
  local console_url=$(oc whoami --show-console 2>/dev/null || echo "unknown")
  log "INFO" "Console URL: $console_url"
  
  local api_url=$(oc whoami --show-server 2>/dev/null || echo "unknown")
  log "INFO" "API URL: $api_url"
  
  return 0
}

# Check storage
check_storage() {
  log "INFO" "Checking storage configuration"
  
  local storage_classes=$(oc get storageclass --no-headers 2>/dev/null | wc -l || echo "0")
  local default_storage=$(oc get storageclass --no-headers 2>/dev/null | grep -c "(default)" || echo "0")
  
  log "INFO" "Storage classes: $storage_classes"
  log "INFO" "Default storage classes: $default_storage"
  
  if [ "$storage_classes" -eq 0 ]; then
    log "WARN" "No storage classes found"
    return 1
  fi
  
  if [ "$default_storage" -eq 0 ]; then
    log "WARN" "No default storage class found"
  fi
  
  return 0
}

# Check networking
check_networking() {
  log "INFO" "Checking networking configuration"
  
  local network_available=$(oc get clusteroperator network -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "unknown")
  
  if [ "$network_available" != "True" ]; then
    log "WARN" "Network operator is not available"
    return 1
  fi
  
  local network_type=$(oc get network.config cluster -o jsonpath='{.spec.networkType}' 2>/dev/null || echo "unknown")
  log "INFO" "Network type: $network_type"
  
  return 0
}

# Run comprehensive validation
run_validation() {
  log "INFO" "Starting comprehensive cluster validation"
  
  local checks=(
    "validate_cluster_connectivity"
    "check_cluster_version"
    "check_node_status"
    "check_cluster_operators"
    "check_critical_pods"
    "check_ingress"
    "check_storage"
    "check_networking"
  )
  
  local passed=0
  local failed=0
  
  for check in "${checks[@]}"; do
    log "INFO" "Running check: $check"
    
    if $check; then
      log "INFO" "✅ $check passed"
      ((passed++))
    else
      log "ERROR" "❌ $check failed"
      ((failed++))
    fi
    
    echo "---"
  done
  
  log "INFO" "Validation summary: $passed passed, $failed failed"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## Cluster Validation Results"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Checks Passed**: $passed"
    add_to_step_summary "- **Checks Failed**: $failed"
    
    if [ $failed -eq 0 ]; then
      add_to_step_summary "- **Status**: ✅ All validations passed"
    else
      add_to_step_summary "- **Status**: ❌ Some validations failed"
    fi
  fi
  
  return $failed
}

# Wait for cluster to be ready
wait_for_cluster_ready() {
  log "INFO" "Waiting for cluster to be ready (timeout: ${TIMEOUT}s)"
  
  local end_time=$(($(date +%s) + TIMEOUT))
  
  while [ $(date +%s) -lt $end_time ]; do
    log "INFO" "Checking cluster readiness..."
    
    if run_validation; then
      log "INFO" "Cluster is ready and all validations passed"
      return 0
    fi
    
    local remaining=$((end_time - $(date +%s)))
    log "INFO" "Cluster not ready yet. Waiting ${CHECK_INTERVAL}s... (${remaining}s remaining)"
    sleep $CHECK_INTERVAL
  done
  
  log "ERROR" "Timeout waiting for cluster to be ready"
  return 1
}

# Main function
main() {
  log "INFO" "Starting cluster validation for $CLUSTER_NAME on $PROVIDER"
  
  # Run validation once or wait for readiness
  if [ "${WAIT_FOR_READY:-false}" = "true" ]; then
    wait_for_cluster_ready
  else
    run_validation
  fi
  
  local exit_code=$?
  
  if [ $exit_code -eq 0 ]; then
    log "INFO" "Cluster validation completed successfully"
  else
    log "ERROR" "Cluster validation failed"
  fi
  
  return $exit_code
}

# Run main function
main "$@"
