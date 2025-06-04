# ADR-007: Azure OpenShift Integration Strategy

**Status:** Proposed  
**Date:** 2025-06-04  
**Authors:** Tosin Akinosho, Sophia AI Assistant  
**Reviewers:** Development Team  

> **Note:** This ADR represents our current understanding and proposed approach. Implementation details may evolve based on research findings, testing results, and new discoveries during the development process. Any significant changes will be documented through ADR updates or new ADRs as appropriate.

## Context

Building on our proven Vault HA deployment (95% success rate) and AWS integration strategy (ADR-006), we need to establish a comprehensive approach for automated Azure Red Hat OpenShift (ARO) deployments using GitHub Actions with dynamic Azure credential management.

### Current State
- ✅ **Vault HA Foundation**: Production-ready with 95% success rate (ADR-001)
- ✅ **AWS Integration**: Defined strategy for AWS OpenShift deployment (ADR-006)
- ✅ **Dynamic Secrets Framework**: Zero-trust credential management (ADR-005)
- ✅ **GitHub Actions Architecture**: Workflow orchestration strategy (ADR-004)
- ⚠️ **Azure Integration Gap**: No Azure-specific deployment automation
- ⚠️ **ARO Deployment Gap**: No Azure Red Hat OpenShift automation

### Azure-Specific Requirements
1. **ARO Deployment**: Automated Azure Red Hat OpenShift installation
2. **Dynamic Azure Credentials**: Just-in-time Service Principal provisioning
3. **Azure Resource Management**: Complete Azure resource lifecycle
4. **GitHub Actions Integration**: Secure CI/CD workflow automation
5. **Azure AD Integration**: Identity and access management
6. **Compliance**: Azure security standards and governance

## Decision

Implement **Azure ARO Deployment with Dynamic Service Principal Integration** using our Vault HA cluster:

### Architecture: Azure OpenShift Deployment Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │             Azure Deployment Workflow              │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │ Vault   │  │ Azure   │  │   ARO   │             │   │
│  │  │ Auth    │  │ Creds   │  │ Deploy  │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ JWT Authentication
                              │ Dynamic Service Principal
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Vault HA  │      │   Azure     │      │    ARO      │
│   Cluster   │      │ Resources   │      │  Cluster    │
│             │      │             │      │             │
│ Azure       │----->│ • Resource  │----->│ • Masters   │
│ Secrets     │      │   Groups    │      │ • Workers   │
│ Engine      │      │ • VNet      │      │ • Ingress   │
│             │      │ • NSG       │      │ • Storage   │
│             │      │ • Service   │      │ • Registry  │
│             │      │   Principal │      │             │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Core Integration Strategy

#### 1. **Azure Secrets Engine Configuration**
```hcl
# Enable Azure secrets engine in Vault
vault secrets enable -path=azure azure

# Configure Azure secrets engine with Service Principal
vault write azure/config \
  subscription_id=$AZURE_SUBSCRIPTION_ID \
  tenant_id=$AZURE_TENANT_ID \
  client_id=$AZURE_CLIENT_ID \
  client_secret=$AZURE_CLIENT_SECRET

# Create role for ARO deployment
vault write azure/roles/aro-deployer \
  azure_roles='[
    {
      "role_name": "Contributor",
      "scope": "/subscriptions/'$AZURE_SUBSCRIPTION_ID'"
    },
    {
      "role_name": "User Access Administrator", 
      "scope": "/subscriptions/'$AZURE_SUBSCRIPTION_ID'"
    }
  ]' \
  ttl=1800 \
  max_ttl=3600
```

#### 2. **Azure Resource Requirements for ARO**
```json
{
  "required_permissions": [
    "Microsoft.RedHatOpenShift/OpenShiftClusters/*",
    "Microsoft.Compute/virtualMachines/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.Network/networkSecurityGroups/*",
    "Microsoft.Network/loadBalancers/*",
    "Microsoft.Network/publicIPAddresses/*",
    "Microsoft.Storage/storageAccounts/*",
    "Microsoft.Authorization/roleAssignments/*",
    "Microsoft.Resources/resourceGroups/*",
    "Microsoft.Resources/subscriptions/resourceGroups/read"
  ],
  "resource_providers": [
    "Microsoft.RedHatOpenShift",
    "Microsoft.Compute",
    "Microsoft.Network",
    "Microsoft.Storage",
    "Microsoft.Authorization"
  ]
}
```

#### 3. **GitHub Actions Workflow for ARO**
```yaml
name: Deploy Azure Red Hat OpenShift
on:
  workflow_dispatch:
    inputs:
      cluster_name:
        description: 'ARO cluster name'
        required: true
      azure_region:
        description: 'Azure region'
        required: true
        default: 'eastus'
      environment:
        description: 'Environment (dev/staging/prod)'
        required: true
        default: 'dev'
      worker_count:
        description: 'Number of worker nodes'
        required: true
        default: '3'

jobs:
  deploy-aro:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Authenticate to Vault
        uses: hashicorp/vault-action@v2
        with:
          url: ${{ secrets.VAULT_URL }}
          method: jwt
          role: github-actions-${{ inputs.environment }}
          secrets: |
            azure/creds/aro-deployer client_id | AZURE_CLIENT_ID ;
            azure/creds/aro-deployer client_secret | AZURE_CLIENT_SECRET
      
      - name: Azure CLI Login
        uses: azure/login@v1
        with:
          creds: |
            {
              "clientId": "${{ env.AZURE_CLIENT_ID }}",
              "clientSecret": "${{ env.AZURE_CLIENT_SECRET }}",
              "subscriptionId": "${{ secrets.AZURE_SUBSCRIPTION_ID }}",
              "tenantId": "${{ secrets.AZURE_TENANT_ID }}"
            }
      
      - name: Create Resource Group
        run: |
          az group create \
            --name rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --location ${{ inputs.azure_region }}
      
      - name: Create Virtual Network
        run: |
          az network vnet create \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --name vnet-aro-${{ inputs.cluster_name }} \
            --address-prefixes 10.0.0.0/22
          
          az network vnet subnet create \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --vnet-name vnet-aro-${{ inputs.cluster_name }} \
            --name master-subnet \
            --address-prefixes 10.0.0.0/23 \
            --service-endpoints Microsoft.ContainerRegistry
          
          az network vnet subnet create \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --vnet-name vnet-aro-${{ inputs.cluster_name }} \
            --name worker-subnet \
            --address-prefixes 10.0.2.0/23 \
            --service-endpoints Microsoft.ContainerRegistry
      
      - name: Disable Subnet Private Endpoint Policies
        run: |
          az network vnet subnet update \
            --name master-subnet \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --vnet-name vnet-aro-${{ inputs.cluster_name }} \
            --disable-private-link-service-network-policies true
      
      - name: Create ARO Cluster
        run: |
          az aro create \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --name aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --vnet vnet-aro-${{ inputs.cluster_name }} \
            --master-subnet master-subnet \
            --worker-subnet worker-subnet \
            --worker-count ${{ inputs.worker_count }} \
            --pull-secret @pull-secret.txt
      
      - name: Get ARO Credentials
        run: |
          # Get cluster credentials
          CONSOLE_URL=$(az aro show \
            --name aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --query consoleProfile.url -o tsv)
          
          API_SERVER=$(az aro show \
            --name aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --query apiserverProfile.url -o tsv)
          
          KUBEADMIN_PASSWORD=$(az aro list-credentials \
            --name aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --resource-group rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            --query kubeadminPassword -o tsv)
          
          # Store credentials in Vault
          vault kv put openshift/clusters/azure-${{ inputs.environment }}-${{ inputs.cluster_name }} \
            console_url="$CONSOLE_URL" \
            api_url="$API_SERVER" \
            kubeadmin_password="$KUBEADMIN_PASSWORD" \
            resource_group="rg-aro-${{ inputs.environment }}-${{ inputs.cluster_name }}" \
            cluster_name="aro-${{ inputs.environment }}-${{ inputs.cluster_name }}"
```

## Consequences

### Positive
- **Azure Native Integration**: Leverages Azure Red Hat OpenShift managed service
- **Reduced Operational Overhead**: Microsoft manages control plane
- **Enterprise Support**: Red Hat and Microsoft joint support
- **Azure AD Integration**: Native identity management
- **Compliance Ready**: Built-in Azure compliance features
- **Scalability**: Azure's global infrastructure
- **Security**: Dynamic Service Principal credentials with short TTL

### Negative
- **Azure Dependency**: Requires Azure subscription and quotas
- **Cost Considerations**: ARO has premium pricing compared to self-managed
- **Limited Customization**: Some OpenShift features may be restricted
- **Regional Availability**: ARO not available in all Azure regions

### Neutral
- **Learning Curve**: Team needs Azure and ARO expertise
- **Vendor Lock-in**: Increased dependency on Azure ecosystem
- **Migration Complexity**: Moving between clouds requires planning

## Implementation

### Phase 1: Azure Secrets Engine Setup (Week 1)
1. **Configure Azure Secrets Engine**
   ```bash
   # Enable Azure secrets engine
   vault secrets enable -path=azure azure
   
   # Configure with Service Principal
   vault write azure/config \
     subscription_id=$AZURE_SUBSCRIPTION_ID \
     tenant_id=$AZURE_TENANT_ID \
     client_id=$AZURE_CLIENT_ID \
     client_secret=$AZURE_CLIENT_SECRET
   
   # Create ARO deployer role
   vault write azure/roles/aro-deployer \
     azure_roles='[{"role_name": "Contributor", "scope": "/subscriptions/'$AZURE_SUBSCRIPTION_ID'"}]'
   ```

2. **Test Dynamic Credential Generation**
   ```bash
   # Test credential generation
   vault read azure/creds/aro-deployer
   
   # Verify credentials work
   az login --service-principal -u $CLIENT_ID -p $CLIENT_SECRET --tenant $TENANT_ID
   az account show
   ```

### Phase 2: ARO Deployment Automation (Week 2)
1. **Create GitHub Actions Workflow**
   - ARO deployment workflow
   - Environment-specific configurations
   - Resource cleanup procedures

2. **Integration Testing**
   - Test Vault authentication from GitHub Actions
   - Validate dynamic Service Principal provisioning
   - End-to-end ARO deployment testing

### Phase 3: Operational Excellence (Week 3)
1. **Monitoring and Alerting**
   - Azure Monitor integration
   - ARO-specific monitoring
   - Cost monitoring and optimization

2. **Backup and Disaster Recovery**
   - etcd backup procedures
   - Cross-region replication strategy
   - Recovery testing

### Success Metrics
- **Deployment Success Rate**: 95% (matching Vault HA success)
- **Deployment Time**: < 60 minutes for complete ARO cluster
- **Security Compliance**: Zero long-lived credentials
- **Cost Optimization**: Automated resource rightsizing

## Alternatives Considered

### Self-Managed OpenShift on Azure VMs
- **Rejected**: Higher operational overhead, no managed service benefits
- **Issues**: Complex setup, manual updates, infrastructure management

### Azure Kubernetes Service (AKS)
- **Rejected**: Not OpenShift, different ecosystem
- **Issues**: Different tooling, no Red Hat support, migration complexity

### Static Azure Service Principal
- **Rejected**: Security risk, no rotation, compliance issues
- **Issues**: Long-lived credentials, manual rotation, audit gaps

### Azure Managed Identity
- **Rejected**: Doesn't solve GitHub Actions authentication
- **Issues**: Still need initial credentials, complex setup

## References

- [Azure Red Hat OpenShift Documentation](https://docs.microsoft.com/en-us/azure/openshift/)
- [Vault Azure Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/azure)
- [Azure Service Principal Best Practices](https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal)
- [GitHub Actions with Azure](https://docs.github.com/en/actions/deployment/deploying-to-your-cloud-provider/deploying-to-azure)
- **Related ADRs**: ADR-003 (Multi-Cloud Integration), ADR-005 (Dynamic Secrets), ADR-006 (AWS Integration)
