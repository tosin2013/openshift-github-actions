#!/bin/bash

# Input validation script for OpenShift multi-cloud deployments
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
REGION=""
NODE_COUNT=""
INSTANCE_TYPE=""
VM_SIZE=""
MACHINE_TYPE=""
BASE_DOMAIN=""
PROJECT_ID=""
OPERATION="deploy"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Validate inputs for OpenShift multi-cloud deployments.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --node-count COUNT          Number of worker nodes
  --instance-type TYPE        AWS instance type
  --vm-size SIZE              Azure VM size
  --machine-type TYPE         GCP machine type
  --base-domain DOMAIN        Base domain for the cluster
  --project-id ID             GCP project ID
  --operation OP              Operation type (deploy, destroy)
  --help                      Show this help message

EXAMPLES:
  # Validate AWS deployment inputs
  $0 --provider aws --cluster-name my-cluster --region us-east-1 \\
     --node-count 3 --instance-type m5.xlarge --base-domain example.com

  # Validate Azure deployment inputs
  $0 --provider azure --cluster-name my-cluster --region eastus \\
     --node-count 3 --vm-size Standard_D4s_v3 --base-domain example.com

  # Validate GCP deployment inputs
  $0 --provider gcp --cluster-name my-cluster --region us-central1 \\
     --node-count 3 --machine-type n1-standard-4 --base-domain example.com \\
     --project-id my-project-123

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
    --node-count)
      NODE_COUNT="$2"
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --vm-size)
      VM_SIZE="$2"
      shift 2
      ;;
    --machine-type)
      MACHINE_TYPE="$2"
      shift 2
      ;;
    --base-domain)
      BASE_DOMAIN="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --operation)
      OPERATION="$2"
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
validate_required_params() {
  local errors=()

  if [ -z "$PROVIDER" ]; then
    errors+=("Provider is required")
  fi

  if [ -z "$CLUSTER_NAME" ]; then
    errors+=("Cluster name is required")
  fi

  if [ -z "$REGION" ]; then
    errors+=("Region is required")
  fi

  if [ "$OPERATION" = "deploy" ]; then
    if [ -z "$BASE_DOMAIN" ]; then
      errors+=("Base domain is required for deployment")
    fi

    if [ -z "$NODE_COUNT" ]; then
      errors+=("Node count is required for deployment")
    fi
  fi

  if [ ${#errors[@]} -gt 0 ]; then
    log "ERROR" "Validation failed:"
    for error in "${errors[@]}"; do
      log "ERROR" "  - $error"
    done
    return 1
  fi

  return 0
}

# Validate provider-specific parameters
validate_provider_params() {
  case "$PROVIDER" in
    aws)
      validate_aws_params
      ;;
    azure)
      validate_azure_params
      ;;
    gcp)
      validate_gcp_params
      ;;
    *)
      log "ERROR" "Unsupported provider: $PROVIDER"
      log "ERROR" "Supported providers: aws, azure, gcp"
      return 1
      ;;
  esac
}

# Validate AWS-specific parameters
validate_aws_params() {
  local errors=()

  # Validate region
  local valid_aws_regions=(
    "us-east-1" "us-east-2" "us-west-1" "us-west-2"
    "eu-west-1" "eu-west-2" "eu-west-3" "eu-central-1"
    "ap-southeast-1" "ap-southeast-2" "ap-northeast-1" "ap-northeast-2"
    "ca-central-1" "sa-east-1"
  )

  if [[ ! " ${valid_aws_regions[*]} " =~ " $REGION " ]]; then
    errors+=("Invalid AWS region: $REGION")
  fi

  # Validate instance type for deployment
  if [ "$OPERATION" = "deploy" ] && [ -n "$INSTANCE_TYPE" ]; then
    local valid_instance_types=(
      "m5.large" "m5.xlarge" "m5.2xlarge" "m5.4xlarge"
      "c5.large" "c5.xlarge" "c5.2xlarge" "c5.4xlarge"
      "r5.large" "r5.xlarge" "r5.2xlarge" "r5.4xlarge"
    )

    if [[ ! " ${valid_instance_types[*]} " =~ " $INSTANCE_TYPE " ]]; then
      errors+=("Invalid AWS instance type: $INSTANCE_TYPE")
    fi
  fi

  if [ ${#errors[@]} -gt 0 ]; then
    log "ERROR" "AWS validation failed:"
    for error in "${errors[@]}"; do
      log "ERROR" "  - $error"
    done
    return 1
  fi

  return 0
}

# Validate Azure-specific parameters
validate_azure_params() {
  local errors=()

  # Validate region
  local valid_azure_regions=(
    "eastus" "eastus2" "westus" "westus2" "westus3"
    "westeurope" "northeurope" "uksouth" "ukwest"
    "southeastasia" "eastasia" "japaneast" "japanwest"
    "australiaeast" "australiasoutheast" "centralindia" "southindia"
  )

  if [[ ! " ${valid_azure_regions[*]} " =~ " $REGION " ]]; then
    errors+=("Invalid Azure region: $REGION")
  fi

  # Validate VM size for deployment
  if [ "$OPERATION" = "deploy" ] && [ -n "$VM_SIZE" ]; then
    local valid_vm_sizes=(
      "Standard_D2s_v3" "Standard_D4s_v3" "Standard_D8s_v3" "Standard_D16s_v3"
      "Standard_F4s_v2" "Standard_F8s_v2" "Standard_F16s_v2"
      "Standard_E4s_v3" "Standard_E8s_v3" "Standard_E16s_v3"
    )

    if [[ ! " ${valid_vm_sizes[*]} " =~ " $VM_SIZE " ]]; then
      errors+=("Invalid Azure VM size: $VM_SIZE")
    fi
  fi

  if [ ${#errors[@]} -gt 0 ]; then
    log "ERROR" "Azure validation failed:"
    for error in "${errors[@]}"; do
      log "ERROR" "  - $error"
    done
    return 1
  fi

  return 0
}

# Validate GCP-specific parameters
validate_gcp_params() {
  local errors=()

  # Validate region
  local valid_gcp_regions=(
    "us-central1" "us-east1" "us-east4" "us-west1" "us-west2" "us-west3" "us-west4"
    "europe-west1" "europe-west2" "europe-west3" "europe-west4" "europe-west6"
    "asia-southeast1" "asia-southeast2" "asia-northeast1" "asia-northeast2" "asia-northeast3"
    "australia-southeast1" "southamerica-east1"
  )

  if [[ ! " ${valid_gcp_regions[*]} " =~ " $REGION " ]]; then
    errors+=("Invalid GCP region: $REGION")
  fi

  # Validate machine type for deployment
  if [ "$OPERATION" = "deploy" ] && [ -n "$MACHINE_TYPE" ]; then
    local valid_machine_types=(
      "n1-standard-2" "n1-standard-4" "n1-standard-8" "n1-standard-16"
      "n2-standard-2" "n2-standard-4" "n2-standard-8" "n2-standard-16"
      "c2-standard-4" "c2-standard-8" "c2-standard-16"
      "e2-standard-2" "e2-standard-4" "e2-standard-8"
    )

    if [[ ! " ${valid_machine_types[*]} " =~ " $MACHINE_TYPE " ]]; then
      errors+=("Invalid GCP machine type: $MACHINE_TYPE")
    fi
  fi

  # Validate project ID for deployment
  if [ "$OPERATION" = "deploy" ] && [ -z "$PROJECT_ID" ]; then
    errors+=("GCP project ID is required for deployment")
  fi

  if [ ${#errors[@]} -gt 0 ]; then
    log "ERROR" "GCP validation failed:"
    for error in "${errors[@]}"; do
      log "ERROR" "  - $error"
    done
    return 1
  fi

  return 0
}

# Validate common parameters
validate_common_params() {
  local errors=()

  # Validate cluster name
  if ! validate_cluster_name "$CLUSTER_NAME"; then
    errors+=("Invalid cluster name format")
  fi

  # Validate base domain for deployment
  if [ "$OPERATION" = "deploy" ] && ! validate_base_domain "$BASE_DOMAIN"; then
    errors+=("Invalid base domain format")
  fi

  # Validate node count for deployment
  if [ "$OPERATION" = "deploy" ] && [ -n "$NODE_COUNT" ]; then
    if ! [[ "$NODE_COUNT" =~ ^[0-9]+$ ]] || [ "$NODE_COUNT" -lt 1 ] || [ "$NODE_COUNT" -gt 100 ]; then
      errors+=("Node count must be a number between 1 and 100")
    fi
  fi

  # Validate operation
  if [[ ! "$OPERATION" =~ ^(deploy|destroy)$ ]]; then
    errors+=("Invalid operation: $OPERATION (must be 'deploy' or 'destroy')")
  fi

  if [ ${#errors[@]} -gt 0 ]; then
    log "ERROR" "Common validation failed:"
    for error in "${errors[@]}"; do
      log "ERROR" "  - $error"
    done
    return 1
  fi

  return 0
}

# Main validation function
main() {
  log "INFO" "Starting input validation for $OPERATION operation"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Region: $REGION"

  # Run all validations
  validate_required_params
  validate_common_params
  validate_provider_params

  log "INFO" "All input validations passed successfully"

  # Add summary to GitHub Actions if running there
  if is_github_actions; then
    add_to_step_summary "## Input Validation Results"
    add_to_step_summary "✅ All input validations passed"
    add_to_step_summary "- **Provider**: $PROVIDER"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Operation**: $OPERATION"
  fi

  return 0
}

# Run main function
main "$@"
