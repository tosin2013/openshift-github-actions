#!/bin/bash

# Cleanup failed OpenShift deployment on Azure
# Author: Tosin Akinosho

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common/utils.sh"

# Default values
CLUSTER_NAME=""
REGION=""
FORCE_CLEANUP=false

# Usage function
usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Cleanup failed OpenShift deployment resources on Azure.

OPTIONS:
  --cluster-name NAME         Cluster name
  --region REGION             Azure region
  --force                     Force cleanup without confirmation
  --help                      Show this help message

EXAMPLES:
  # Cleanup failed deployment
  $0 --cluster-name my-cluster --region eastus

  # Force cleanup without confirmation
  $0 --cluster-name my-cluster --region eastus --force

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
if [ -z "$CLUSTER_NAME" ] || [ -z "$REGION" ]; then
  log "ERROR" "Missing required parameters"
  usage
  exit 1
fi

# Check if Azure CLI is available
if ! command_exists az; then
  log "ERROR" "Azure CLI is not installed or not in PATH"
  exit 1
fi

# Validate Azure credentials
validate_azure_credentials() {
  log "INFO" "Validating Azure credentials"
  
  if ! az account show >/dev/null 2>&1; then
    log "ERROR" "Azure credentials are not valid or not configured"
    exit 1
  fi
  
  log "INFO" "Azure credentials validated"
}

# Confirm cleanup
confirm_cleanup() {
  if [ "$FORCE_CLEANUP" = "true" ]; then
    log "INFO" "Force cleanup enabled, skipping confirmation"
    return 0
  fi
  
  log "WARN" "This will attempt to cleanup Azure resources for cluster: $CLUSTER_NAME"
  log "WARN" "This action cannot be undone!"
  
  read -p "Are you sure you want to proceed? (yes/no): " confirmation
  
  if [ "$confirmation" != "yes" ]; then
    log "INFO" "Cleanup cancelled by user"
    exit 0
  fi
}

# Find and cleanup resource groups
cleanup_resource_groups() {
  log "INFO" "Cleaning up resource groups"
  
  local resource_groups=$(az group list \
    --query "[?contains(name, '$CLUSTER_NAME')].name" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$resource_groups" ]; then
    log "INFO" "Found resource groups to delete: $resource_groups"
    
    for rg in $resource_groups; do
      log "INFO" "Deleting resource group: $rg"
      az group delete --name "$rg" --yes --no-wait
      log "INFO" "Deletion initiated for resource group: $rg"
    done
    
    log "INFO" "Resource group deletions initiated (running in background)"
  else
    log "INFO" "No resource groups found for cleanup"
  fi
}

# Cleanup virtual machines
cleanup_virtual_machines() {
  log "INFO" "Cleaning up virtual machines"
  
  local vms=$(az vm list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$vms" ]; then
    log "INFO" "Found virtual machines to delete"
    
    while IFS=$'\t' read -r vm_name resource_group; do
      if [ -n "$vm_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting VM: $vm_name in resource group: $resource_group"
        az vm delete --name "$vm_name" --resource-group "$resource_group" --yes --no-wait
      fi
    done <<< "$vms"
    
    log "INFO" "VM deletions initiated"
  else
    log "INFO" "No virtual machines found for cleanup"
  fi
}

# Cleanup network security groups
cleanup_network_security_groups() {
  log "INFO" "Cleaning up network security groups"
  
  local nsgs=$(az network nsg list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$nsgs" ]; then
    log "INFO" "Found network security groups to delete"
    
    while IFS=$'\t' read -r nsg_name resource_group; do
      if [ -n "$nsg_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting NSG: $nsg_name in resource group: $resource_group"
        az network nsg delete --name "$nsg_name" --resource-group "$resource_group" --no-wait
      fi
    done <<< "$nsgs"
    
    log "INFO" "NSG deletions initiated"
  else
    log "INFO" "No network security groups found for cleanup"
  fi
}

# Cleanup load balancers
cleanup_load_balancers() {
  log "INFO" "Cleaning up load balancers"
  
  local lbs=$(az network lb list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$lbs" ]; then
    log "INFO" "Found load balancers to delete"
    
    while IFS=$'\t' read -r lb_name resource_group; do
      if [ -n "$lb_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting load balancer: $lb_name in resource group: $resource_group"
        az network lb delete --name "$lb_name" --resource-group "$resource_group" --no-wait
      fi
    done <<< "$lbs"
    
    log "INFO" "Load balancer deletions initiated"
  else
    log "INFO" "No load balancers found for cleanup"
  fi
}

# Cleanup public IPs
cleanup_public_ips() {
  log "INFO" "Cleaning up public IPs"
  
  local public_ips=$(az network public-ip list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$public_ips" ]; then
    log "INFO" "Found public IPs to delete"
    
    while IFS=$'\t' read -r ip_name resource_group; do
      if [ -n "$ip_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting public IP: $ip_name in resource group: $resource_group"
        az network public-ip delete --name "$ip_name" --resource-group "$resource_group" --no-wait
      fi
    done <<< "$public_ips"
    
    log "INFO" "Public IP deletions initiated"
  else
    log "INFO" "No public IPs found for cleanup"
  fi
}

# Cleanup storage accounts
cleanup_storage_accounts() {
  log "INFO" "Cleaning up storage accounts"
  
  local storage_accounts=$(az storage account list \
    --query "[?contains(name, '$(echo $CLUSTER_NAME | tr -d '-' | tr '[:upper:]' '[:lower:]')')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$storage_accounts" ]; then
    log "INFO" "Found storage accounts to delete"
    
    while IFS=$'\t' read -r storage_name resource_group; do
      if [ -n "$storage_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting storage account: $storage_name in resource group: $resource_group"
        az storage account delete --name "$storage_name" --resource-group "$resource_group" --yes
      fi
    done <<< "$storage_accounts"
    
    log "INFO" "Storage account deletions completed"
  else
    log "INFO" "No storage accounts found for cleanup"
  fi
}

# Cleanup virtual networks
cleanup_virtual_networks() {
  log "INFO" "Cleaning up virtual networks"
  
  local vnets=$(az network vnet list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$vnets" ]; then
    log "INFO" "Found virtual networks to delete"
    
    while IFS=$'\t' read -r vnet_name resource_group; do
      if [ -n "$vnet_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting virtual network: $vnet_name in resource group: $resource_group"
        az network vnet delete --name "$vnet_name" --resource-group "$resource_group" --no-wait
      fi
    done <<< "$vnets"
    
    log "INFO" "Virtual network deletions initiated"
  else
    log "INFO" "No virtual networks found for cleanup"
  fi
}

# Cleanup DNS zones
cleanup_dns_zones() {
  log "INFO" "Cleaning up DNS zones"
  
  local dns_zones=$(az network dns zone list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$dns_zones" ]; then
    log "WARN" "Found DNS zones that may need manual cleanup: $dns_zones"
    log "WARN" "Please review and cleanup DNS zones manually if needed"
  else
    log "INFO" "No DNS zones found for cleanup"
  fi
}

# Cleanup managed identities
cleanup_managed_identities() {
  log "INFO" "Cleaning up managed identities"
  
  local identities=$(az identity list \
    --query "[?contains(name, '$CLUSTER_NAME')].{name:name, resourceGroup:resourceGroup}" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$identities" ]; then
    log "INFO" "Found managed identities to delete"
    
    while IFS=$'\t' read -r identity_name resource_group; do
      if [ -n "$identity_name" ] && [ -n "$resource_group" ]; then
        log "INFO" "Deleting managed identity: $identity_name in resource group: $resource_group"
        az identity delete --name "$identity_name" --resource-group "$resource_group"
      fi
    done <<< "$identities"
    
    log "INFO" "Managed identity deletions completed"
  else
    log "INFO" "No managed identities found for cleanup"
  fi
}

# Wait for resource group deletions
wait_for_cleanup() {
  log "INFO" "Waiting for resource group deletions to complete"
  
  local resource_groups=$(az group list \
    --query "[?contains(name, '$CLUSTER_NAME')].name" \
    --output tsv 2>/dev/null || echo "")
  
  if [ -n "$resource_groups" ]; then
    log "INFO" "Monitoring resource group deletions..."
    
    local timeout=1800  # 30 minutes
    local start_time=$(date +%s)
    
    while [ -n "$resource_groups" ] && [ $(($(date +%s) - start_time)) -lt $timeout ]; do
      sleep 30
      resource_groups=$(az group list \
        --query "[?contains(name, '$CLUSTER_NAME')].name" \
        --output tsv 2>/dev/null || echo "")
      
      if [ -n "$resource_groups" ]; then
        log "INFO" "Still waiting for resource groups to be deleted: $resource_groups"
      fi
    done
    
    if [ -n "$resource_groups" ]; then
      log "WARN" "Timeout waiting for resource group deletions. Remaining: $resource_groups"
    else
      log "INFO" "All resource groups have been deleted"
    fi
  fi
}

# Main cleanup function
main() {
  log "INFO" "Starting Azure cleanup for cluster: $CLUSTER_NAME"
  log "INFO" "Region: $REGION"
  
  # Validate prerequisites
  validate_azure_credentials
  
  # Confirm cleanup
  confirm_cleanup
  
  # Run cleanup steps (order matters for dependencies)
  cleanup_virtual_machines
  cleanup_load_balancers
  cleanup_public_ips
  cleanup_network_security_groups
  cleanup_storage_accounts
  cleanup_virtual_networks
  cleanup_dns_zones
  cleanup_managed_identities
  
  # Cleanup resource groups (this will clean up any remaining resources)
  cleanup_resource_groups
  
  # Wait for cleanup to complete
  wait_for_cleanup
  
  log "INFO" "Azure cleanup completed"
  log "WARN" "Please verify that all resources have been cleaned up properly"
  
  # Add to GitHub Actions summary if available
  if is_github_actions; then
    add_to_step_summary "## Azure Cleanup Completed"
    add_to_step_summary "⚠️ Cleanup attempted for failed deployment"
    add_to_step_summary "- **Cluster**: $CLUSTER_NAME"
    add_to_step_summary "- **Region**: $REGION"
    add_to_step_summary ""
    add_to_step_summary "**Cleanup Actions:**"
    add_to_step_summary "- Virtual machines deleted"
    add_to_step_summary "- Load balancers removed"
    add_to_step_summary "- Network security groups deleted"
    add_to_step_summary "- Storage accounts cleaned up"
    add_to_step_summary "- Virtual networks removed"
    add_to_step_summary "- Managed identities deleted"
    add_to_step_summary "- Resource groups deleted"
    add_to_step_summary ""
    add_to_step_summary "⚠️ **Please verify all resources were cleaned up properly**"
  fi
  
  return 0
}

# Run main function
main "$@"
