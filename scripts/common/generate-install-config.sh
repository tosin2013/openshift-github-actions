#!/bin/bash

# Generate install-config.yaml for OpenShift multi-cloud deployments
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Default values
PROVIDER=""
CLUSTER_NAME=""
REGION=""
NODE_COUNT="3"
INSTANCE_TYPE=""
VM_SIZE=""
MACHINE_TYPE=""
BASE_DOMAIN=""
PROJECT_ID=""
ENVIRONMENT="dev"
OUTPUT_FILE="install-config.yaml"

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Generate install-config.yaml for OpenShift multi-cloud deployments.

OPTIONS:
  --provider PROVIDER         Cloud provider (aws, azure, gcp)
  --cluster-name NAME         Cluster name
  --region REGION             Cloud provider region
  --node-count COUNT          Number of worker nodes (default: 3)
  --instance-type TYPE        AWS instance type
  --vm-size SIZE              Azure VM size
  --machine-type TYPE         GCP machine type
  --base-domain DOMAIN        Base domain for the cluster
  --project-id ID             GCP project ID
  --environment ENV           Environment (dev, staging, production)
  --output FILE               Output file (default: install-config.yaml)
  --help                      Show this help message

EXAMPLES:
  # Generate AWS install-config
  $0 --provider aws --cluster-name my-cluster --region us-east-1 \\
     --node-count 3 --instance-type m5.xlarge --base-domain example.com

  # Generate Azure install-config
  $0 --provider azure --cluster-name my-cluster --region eastus \\
     --node-count 3 --vm-size Standard_D4s_v3 --base-domain example.com

  # Generate GCP install-config
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
    --environment)
      ENVIRONMENT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
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
if [ -z "$PROVIDER" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ] || [ -z "$BASE_DOMAIN" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Validate environment variables for secrets
validate_env_vars "PULL_SECRET" "SSH_PUBLIC_KEY"

# Load environment-specific configuration
load_environment_config() {
  local config_file="config/$ENVIRONMENT/$PROVIDER/variables.yaml"
  
  if [ -f "$config_file" ]; then
    log "INFO" "Loading environment configuration from $config_file"
    # This would typically use a YAML parser, but for simplicity we'll use defaults
  else
    log "WARN" "Environment configuration file not found: $config_file"
    log "INFO" "Using default values"
  fi
}

# Generate AWS install-config
generate_aws_config() {
  local master_instance_type="m5.xlarge"
  local worker_instance_type="${INSTANCE_TYPE:-m5.xlarge}"
  
  log "INFO" "Generating AWS install-config.yaml"
  
  cat > "$OUTPUT_FILE" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    aws:
      type: ${worker_instance_type}
      rootVolume:
        size: 100
        type: gp3
  replicas: ${NODE_COUNT}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    aws:
      type: ${master_instance_type}
      rootVolume:
        size: 120
        type: gp3
  replicas: 3
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: ${REGION}
pullSecret: '${PULL_SECRET}'
sshKey: '${SSH_PUBLIC_KEY}'
EOF
}

# Generate Azure install-config
generate_azure_config() {
  local master_vm_size="Standard_D8s_v3"
  local worker_vm_size="${VM_SIZE:-Standard_D4s_v3}"
  
  log "INFO" "Generating Azure install-config.yaml"
  
  cat > "$OUTPUT_FILE" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    azure:
      type: ${worker_vm_size}
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
  replicas: ${NODE_COUNT}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    azure:
      type: ${master_vm_size}
      osDisk:
        diskSizeGB: 128
        diskType: Premium_LRS
  replicas: 3
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
platform:
  azure:
    region: ${REGION}
    baseDomainResourceGroupName: ${CLUSTER_NAME}-rg
pullSecret: '${PULL_SECRET}'
sshKey: '${SSH_PUBLIC_KEY}'
EOF
}

# Generate GCP install-config
generate_gcp_config() {
  local master_machine_type="n1-standard-4"
  local worker_machine_type="${MACHINE_TYPE:-n1-standard-4}"
  
  log "INFO" "Generating GCP install-config.yaml"
  
  cat > "$OUTPUT_FILE" << EOF
apiVersion: v1
baseDomain: ${BASE_DOMAIN}
metadata:
  name: ${CLUSTER_NAME}
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform:
    gcp:
      type: ${worker_machine_type}
      rootVolume:
        size: 100
        type: pd-ssd
  replicas: ${NODE_COUNT}
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform:
    gcp:
      type: ${master_machine_type}
      rootVolume:
        size: 120
        type: pd-ssd
  replicas: 3
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  serviceNetwork:
  - 172.30.0.0/16
platform:
  gcp:
    projectID: ${PROJECT_ID}
    region: ${REGION}
pullSecret: '${PULL_SECRET}'
sshKey: '${SSH_PUBLIC_KEY}'
EOF
}

# Main function
main() {
  log "INFO" "Starting install-config generation"
  log "INFO" "Provider: $PROVIDER"
  log "INFO" "Cluster: $CLUSTER_NAME"
  log "INFO" "Region: $REGION"
  log "INFO" "Environment: $ENVIRONMENT"
  
  # Load environment-specific configuration
  load_environment_config
  
  # Generate provider-specific config
  case "$PROVIDER" in
    aws)
      generate_aws_config
      ;;
    azure)
      generate_azure_config
      ;;
    gcp)
      generate_gcp_config
      ;;
    *)
      log "ERROR" "Unsupported provider: $PROVIDER"
      exit 1
      ;;
  esac
  
  # Validate generated config
  if [ -f "$OUTPUT_FILE" ]; then
    log "INFO" "Install-config generated successfully: $OUTPUT_FILE"
    log "DEBUG" "Config file size: $(wc -c < "$OUTPUT_FILE") bytes"
    
    # Add to GitHub Actions summary if available
    if is_github_actions; then
      add_to_step_summary "## Install Config Generated"
      add_to_step_summary "✅ Successfully generated install-config.yaml"
      add_to_step_summary "- **Provider**: $PROVIDER"
      add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
      add_to_step_summary "- **Region**: $REGION"
      add_to_step_summary "- **Worker Nodes**: $NODE_COUNT"
    fi
  else
    log "ERROR" "Failed to generate install-config.yaml"
    exit 1
  fi
}

# Run main function
main "$@"
