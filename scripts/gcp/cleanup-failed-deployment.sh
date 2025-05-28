#!/bin/bash

# Cleanup failed OpenShift deployment on GCP
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

# Default values
CLUSTER_NAME=""
REGION=""
PROJECT_ID=""
FORCE_CLEANUP=false

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Cleanup failed OpenShift deployment resources on GCP.

OPTIONS:
  --cluster-name NAME         Cluster name
  --region REGION             GCP region
  --project-id ID             GCP project ID
  --force                     Force cleanup without confirmation
  --help                      Show this help message

EXAMPLES:
  # Cleanup failed deployment
  $0 --cluster-name my-cluster --region us-central1 --project-id my-project

  # Force cleanup without confirmation
  $0 --cluster-name my-cluster --region us-central1 --project-id my-project --force

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --cluster-name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --region)
      REGION="$2"
      shift 2
      ;;
    --project-id)
      PROJECT_ID="$2"
      shift 2
      ;;
    --force)
      FORCE_CLEANUP=true
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
if [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ] || [ -z "$PROJECT_ID" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Check if gcloud CLI is available
if ! command_exists gcloud; then
  log "ERROR" "Google Cloud CLI is not installed or not in PATH"
  exit 1
fi

# Validate GCP credentials
validate_gcp_credentials() {
  log "INFO" "Validating GCP credentials"
  
  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -n1 >/dev/null 2>&1; then
    log "ERROR" "GCP credentials are not valid or not configured"
    exit 1
  fi
  
  # Set project
  gcloud config set project "$PROJECT_ID"
  
  log "INFO" "GCP credentials validated for project: $PROJECT_ID"
}

# Confirm cleanup
confirm_cleanup() {
  if [ "$FORCE_CLEANUP" = "true" ]; then
    log "INFO" "Force cleanup enabled, skipping confirmation"
    return 0
  fi
  
  log "WARN" "This will attempt to cleanup GCP resources for cluster: $CLUSTER_NAME"
  log "WARN" "This action cannot be undone!"
  
  read -p "Are you sure you want to proceed? (yes/no): " confirmation
  
  if [ "$confirmation" != "yes" ]; then
    log "INFO" "Cleanup cancelled by user"
    exit 0
  fi
}

# Cleanup compute instances
cleanup_compute_instances() {
  log "INFO" "Cleaning up compute instances"
  
  local instances=$(gcloud compute instances list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,zone)" 2>/dev/null || echo "")
  
  if [ -n "$instances" ]; then
    log "INFO" "Found compute instances to delete"
    
    while IFS=$'\t' read -r instance_name zone; do
      if [ -n "$instance_name" ] && [ -n "$zone" ]; then
        log "INFO" "Deleting instance: $instance_name in zone: $zone"
        gcloud compute instances delete "$instance_name" \
          --project="$PROJECT_ID" \
          --zone="$zone" \
          --quiet &
      fi
    done <<< "$instances"
    
    wait
    log "INFO" "Compute instance deletions completed"
  else
    log "INFO" "No compute instances found for cleanup"
  fi
}

# Cleanup instance groups
cleanup_instance_groups() {
  log "INFO" "Cleaning up instance groups"
  
  # Managed instance groups
  local migs=$(gcloud compute instance-groups managed list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,zone)" 2>/dev/null || echo "")
  
  if [ -n "$migs" ]; then
    log "INFO" "Found managed instance groups to delete"
    
    while IFS=$'\t' read -r mig_name zone; do
      if [ -n "$mig_name" ] && [ -n "$zone" ]; then
        log "INFO" "Deleting managed instance group: $mig_name in zone: $zone"
        gcloud compute instance-groups managed delete "$mig_name" \
          --project="$PROJECT_ID" \
          --zone="$zone" \
          --quiet
      fi
    done <<< "$migs"
  fi
  
  # Unmanaged instance groups
  local uigs=$(gcloud compute instance-groups unmanaged list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,zone)" 2>/dev/null || echo "")
  
  if [ -n "$uigs" ]; then
    log "INFO" "Found unmanaged instance groups to delete"
    
    while IFS=$'\t' read -r uig_name zone; do
      if [ -n "$uig_name" ] && [ -n "$zone" ]; then
        log "INFO" "Deleting unmanaged instance group: $uig_name in zone: $zone"
        gcloud compute instance-groups unmanaged delete "$uig_name" \
          --project="$PROJECT_ID" \
          --zone="$zone" \
          --quiet
      fi
    done <<< "$uigs"
  fi
  
  if [ -z "$migs" ] && [ -z "$uigs" ]; then
    log "INFO" "No instance groups found for cleanup"
  fi
}

# Cleanup load balancers
cleanup_load_balancers() {
  log "INFO" "Cleaning up load balancers"
  
  # Backend services
  local backend_services=$(gcloud compute backend-services list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  for service in $backend_services; do
    if [ -n "$service" ]; then
      log "INFO" "Deleting backend service: $service"
      gcloud compute backend-services delete "$service" \
        --project="$PROJECT_ID" \
        --global \
        --quiet
    fi
  done
  
  # URL maps
  local url_maps=$(gcloud compute url-maps list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  for url_map in $url_maps; do
    if [ -n "$url_map" ]; then
      log "INFO" "Deleting URL map: $url_map"
      gcloud compute url-maps delete "$url_map" \
        --project="$PROJECT_ID" \
        --global \
        --quiet
    fi
  done
  
  # Target HTTP(S) proxies
  local http_proxies=$(gcloud compute target-http-proxies list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  for proxy in $http_proxies; do
    if [ -n "$proxy" ]; then
      log "INFO" "Deleting HTTP proxy: $proxy"
      gcloud compute target-http-proxies delete "$proxy" \
        --project="$PROJECT_ID" \
        --global \
        --quiet
    fi
  done
  
  local https_proxies=$(gcloud compute target-https-proxies list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  for proxy in $https_proxies; do
    if [ -n "$proxy" ]; then
      log "INFO" "Deleting HTTPS proxy: $proxy"
      gcloud compute target-https-proxies delete "$proxy" \
        --project="$PROJECT_ID" \
        --global \
        --quiet
    fi
  done
  
  # Forwarding rules
  local forwarding_rules=$(gcloud compute forwarding-rules list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,region)" 2>/dev/null || echo "")
  
  while IFS=$'\t' read -r rule_name region; do
    if [ -n "$rule_name" ]; then
      if [ -n "$region" ]; then
        log "INFO" "Deleting regional forwarding rule: $rule_name in region: $region"
        gcloud compute forwarding-rules delete "$rule_name" \
          --project="$PROJECT_ID" \
          --region="$region" \
          --quiet
      else
        log "INFO" "Deleting global forwarding rule: $rule_name"
        gcloud compute forwarding-rules delete "$rule_name" \
          --project="$PROJECT_ID" \
          --global \
          --quiet
      fi
    fi
  done <<< "$forwarding_rules"
  
  if [ -z "$backend_services" ] && [ -z "$url_maps" ] && [ -z "$http_proxies" ] && [ -z "$https_proxies" ] && [ -z "$forwarding_rules" ]; then
    log "INFO" "No load balancers found for cleanup"
  fi
}

# Cleanup firewall rules
cleanup_firewall_rules() {
  log "INFO" "Cleaning up firewall rules"
  
  local firewall_rules=$(gcloud compute firewall-rules list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  if [ -n "$firewall_rules" ]; then
    log "INFO" "Found firewall rules to delete: $firewall_rules"
    
    for rule in $firewall_rules; do
      if [ -n "$rule" ]; then
        log "INFO" "Deleting firewall rule: $rule"
        gcloud compute firewall-rules delete "$rule" \
          --project="$PROJECT_ID" \
          --quiet
      fi
    done
  else
    log "INFO" "No firewall rules found for cleanup"
  fi
}

# Cleanup disks
cleanup_disks() {
  log "INFO" "Cleaning up disks"
  
  local disks=$(gcloud compute disks list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,zone)" 2>/dev/null || echo "")
  
  if [ -n "$disks" ]; then
    log "INFO" "Found disks to delete"
    
    while IFS=$'\t' read -r disk_name zone; do
      if [ -n "$disk_name" ] && [ -n "$zone" ]; then
        log "INFO" "Deleting disk: $disk_name in zone: $zone"
        gcloud compute disks delete "$disk_name" \
          --project="$PROJECT_ID" \
          --zone="$zone" \
          --quiet &
      fi
    done <<< "$disks"
    
    wait
    log "INFO" "Disk deletions completed"
  else
    log "INFO" "No disks found for cleanup"
  fi
}

# Cleanup storage buckets
cleanup_storage_buckets() {
  log "INFO" "Cleaning up storage buckets"
  
  local buckets=$(gsutil ls -p "$PROJECT_ID" 2>/dev/null | grep "$CLUSTER_NAME" || echo "")
  
  if [ -n "$buckets" ]; then
    log "INFO" "Found storage buckets to delete: $buckets"
    
    for bucket in $buckets; do
      if [ -n "$bucket" ]; then
        log "INFO" "Deleting storage bucket: $bucket"
        gsutil -m rm -r "$bucket" 2>/dev/null || true
      fi
    done
  else
    log "INFO" "No storage buckets found for cleanup"
  fi
}

# Cleanup VPC networks
cleanup_vpc_networks() {
  log "INFO" "Cleaning up VPC networks"
  
  # Subnets first
  local subnets=$(gcloud compute networks subnets list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name,region)" 2>/dev/null || echo "")
  
  while IFS=$'\t' read -r subnet_name region; do
    if [ -n "$subnet_name" ] && [ -n "$region" ]; then
      log "INFO" "Deleting subnet: $subnet_name in region: $region"
      gcloud compute networks subnets delete "$subnet_name" \
        --project="$PROJECT_ID" \
        --region="$region" \
        --quiet
    fi
  done <<< "$subnets"
  
  # Networks
  local networks=$(gcloud compute networks list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  for network in $networks; do
    if [ -n "$network" ]; then
      log "INFO" "Deleting network: $network"
      gcloud compute networks delete "$network" \
        --project="$PROJECT_ID" \
        --quiet
    fi
  done
  
  if [ -z "$subnets" ] && [ -z "$networks" ]; then
    log "INFO" "No VPC networks found for cleanup"
  fi
}

# Cleanup DNS zones
cleanup_dns_zones() {
  log "INFO" "Cleaning up DNS zones"
  
  local dns_zones=$(gcloud dns managed-zones list \
    --project="$PROJECT_ID" \
    --filter="name~'$CLUSTER_NAME'" \
    --format="value(name)" 2>/dev/null || echo "")
  
  if [ -n "$dns_zones" ]; then
    log "WARN" "Found DNS zones that may need manual cleanup: $dns_zones"
    log "WARN" "Please review and cleanup DNS zones manually if needed"
  else
    log "INFO" "No DNS zones found for cleanup"
  fi
}

# Cleanup service accounts
cleanup_service_accounts() {
  log "INFO" "Cleaning up service accounts"
  
  local service_accounts=$(gcloud iam service-accounts list \
    --project="$PROJECT_ID" \
    --filter="email~'$CLUSTER_NAME'" \
    --format="value(email)" 2>/dev/null || echo "")
  
  if [ -n "$service_accounts" ]; then
    log "INFO" "Found service accounts to delete: $service_accounts"
    
    for sa in $service_accounts; do
      if [ -n "$sa" ]; then
        log "INFO" "Deleting service account: $sa"
        gcloud iam service-accounts delete "$sa" \
          --project="$PROJECT_ID" \
          --quiet
      fi
    done
  else
    log "INFO" "No service accounts found for cleanup"
  fi
}

# Main cleanup function
main() {
  log "INFO" "Starting GCP cleanup for cluster: $CLUSTER_NAME"
  log "INFO" "Region: $REGION"
  log "INFO" "Project: $PROJECT_ID"
  
  # Validate prerequisites
  validate_gcp_credentials
  
  # Confirm cleanup
  confirm_cleanup
  
  # Run cleanup steps (order matters for dependencies)
  cleanup_compute_instances
  cleanup_instance_groups
  cleanup_load_balancers
  cleanup_firewall_rules
  cleanup_disks
  cleanup_storage_buckets
  cleanup_service_accounts
  cleanup_vpc_networks
  cleanup_dns_zones
  
  log "INFO" "GCP cleanup completed"
  log "WARN" "Please verify that all resources have been cleaned up properly"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## GCP Cleanup Completed"
    add_to_step_summary "⚠️ Cleanup attempted for failed deployment"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary "- **Project**: $PROJECT_ID"
    add_to_step_summary ""
    add_to_step_summary "**Cleanup Actions:**"
    add_to_step_summary "- Compute instances deleted"
    add_to_step_summary "- Instance groups removed"
    add_to_step_summary "- Load balancers deleted"
    add_to_step_summary "- Firewall rules removed"
    add_to_step_summary "- Disks deleted"
    add_to_step_summary "- Storage buckets cleaned up"
    add_to_step_summary "- Service accounts removed"
    add_to_step_summary "- VPC networks deleted"
    add_to_step_summary ""
    add_to_step_summary "⚠️ **Please verify all resources were cleaned up properly**"
  fi
  
  return 0
}

# Run main function
main "$@"
