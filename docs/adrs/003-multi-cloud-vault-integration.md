# ADR-003: Multi-Cloud Vault Integration Strategy

**Status:** Proposed  
**Date:** 2025-06-04  
**Authors:** Tosin Akinosho, Sophia AI Assistant  
**Reviewers:** Development Team  

## Context

With our proven 95/100 success rate Vault HA deployment on OpenShift, we need to establish how this Vault instance will serve as the centralized secrets management backbone for multi-cloud OpenShift automation across AWS, Azure, and GCP.

### Current State
- ✅ **Vault HA Cluster**: Production-ready with 95% deployment success rate
- ✅ **TLS Integration**: End-to-end encryption with cert-manager
- ✅ **OpenShift Native**: Deployed and operational on OpenShift
- ⚠️ **Multi-Cloud Gap**: No integration with cloud provider credentials
- ⚠️ **GitHub Actions Gap**: No CI/CD integration for automated deployments

### Requirements
1. **Centralized Secrets Management**: Single Vault instance managing all cloud credentials
2. **Dynamic Credentials**: Just-in-time credential provisioning for security
3. **Multi-Cloud Support**: AWS, Azure, GCP secrets engines
4. **GitHub Actions Integration**: Secure authentication for CI/CD workflows
5. **High Availability**: Leverage existing HA cluster for reliability
6. **Security**: Least-privilege access with credential rotation

## Decision

Implement a **Hub-and-Spoke Vault Integration Model** using our existing Vault HA cluster as the central hub:

### Architecture: Central Vault Hub Model

```
┌─────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Vault HA Cluster                       │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │vault-0  │  │vault-1  │  │vault-2  │             │   │
│  │  │(leader) │  │(standby)│  │(standby)│             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  │                                                     │   │
│  │  Secrets Engines:                                   │   │
│  │  ├── AWS Secrets Engine                             │   │
│  │  ├── Azure Secrets Engine                           │   │
│  │  ├── GCP Secrets Engine                             │   │
│  │  ├── KV v2 (OpenShift Secrets)                      │   │
│  │  └── PKI (Certificate Management)                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTPS/TLS
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   AWS       │      │   Azure     │      │    GCP      │
│ OpenShift   │      │ OpenShift   │      │ OpenShift   │
│ Clusters    │      │ Clusters    │      │ Clusters    │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Core Integration Strategy

#### 1. **Secrets Engine Configuration**
```hcl
# AWS Secrets Engine
vault auth enable aws
vault secrets enable -path=aws aws

# Azure Secrets Engine  
vault secrets enable -path=azure azure

# GCP Secrets Engine
vault secrets enable -path=gcp gcp

# OpenShift Secrets (KV v2)
vault secrets enable -path=openshift kv-v2

# PKI for Certificate Management
vault secrets enable -path=pki pki
```

#### 2. **Authentication Methods**
- **GitHub Actions**: JWT authentication with OIDC
- **OpenShift Clusters**: Kubernetes authentication
- **Administrators**: LDAP/OIDC for human access

#### 3. **Network Architecture**
- **Internal Access**: OpenShift route with TLS passthrough
- **External Access**: Secured via OpenShift ingress with proper network policies
- **Cross-Cloud**: HTTPS over public internet with mutual TLS

## Consequences

### Positive
- **Leverages Proven Infrastructure**: 95% success rate Vault HA cluster
- **Centralized Security**: Single point of secrets management and audit
- **Dynamic Credentials**: Enhanced security with just-in-time provisioning
- **Cost Effective**: Single Vault cluster serves all clouds
- **Simplified Operations**: One Vault instance to manage and monitor
- **High Availability**: Existing HA cluster provides reliability
- **Scalable**: Can handle multiple OpenShift clusters per cloud

### Negative
- **Single Point of Failure**: All clouds depend on one Vault instance
- **Network Dependency**: Cross-cloud connectivity required
- **Latency Considerations**: Geographic distance may impact performance
- **Complexity**: Advanced Vault configuration required

### Neutral
- **Learning Curve**: Team needs Vault secrets engine expertise
- **Monitoring Requirements**: Need comprehensive Vault monitoring
- **Backup Strategy**: Critical to backup Vault data regularly

## Implementation

### Phase 1: Secrets Engine Setup
1. **Configure AWS Secrets Engine**
   ```bash
   vault write aws/config/root \
     access_key=$AWS_ACCESS_KEY \
     secret_key=$AWS_SECRET_KEY \
     region=us-east-1
   
   vault write aws/roles/openshift-installer \
     credential_type=iam_user \
     policy_document=@aws-openshift-policy.json
   ```

2. **Configure Azure Secrets Engine**
   ```bash
   vault write azure/config \
     subscription_id=$AZURE_SUBSCRIPTION_ID \
     tenant_id=$AZURE_TENANT_ID \
     client_id=$AZURE_CLIENT_ID \
     client_secret=$AZURE_CLIENT_SECRET
   
   vault write azure/roles/openshift-installer \
     azure_roles=@azure-openshift-roles.json
   ```

3. **Configure GCP Secrets Engine**
   ```bash
   vault write gcp/config \
     credentials=@gcp-service-account.json
   
   vault write gcp/roleset/openshift-installer \
     project=$GCP_PROJECT_ID \
     secret_type=service_account_key \
     bindings=@gcp-openshift-bindings.hcl
   ```

### Phase 2: Authentication Integration
1. **GitHub Actions JWT Authentication**
2. **Kubernetes Authentication for OpenShift Clusters**
3. **Policy Configuration for Least-Privilege Access**

### Phase 3: GitHub Actions Integration
1. **Workflow Templates for Each Cloud Provider**
2. **Dynamic Credential Retrieval**
3. **Automated Vault Deployment as Prerequisite**

### Success Metrics
- **Credential Provisioning**: < 30 seconds for dynamic credentials
- **Security**: Zero long-lived credentials in workflows
- **Reliability**: 99.9% Vault availability for credential requests
- **Audit**: Complete audit trail for all credential access

## Alternatives Considered

### Regional Vault Clusters
- **Rejected**: Adds complexity without significant benefit
- **Issues**: Data synchronization, increased operational overhead

### Cloud-Native Secret Managers
- **Rejected**: Vendor lock-in, inconsistent APIs across clouds
- **Issues**: AWS Secrets Manager, Azure Key Vault, GCP Secret Manager differences

### External Vault Service (HCP)
- **Rejected**: We have proven on-premises solution
- **Issues**: Additional cost, less control, network dependencies

## References

- [Vault AWS Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/aws)
- [Vault Azure Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/azure)
- [Vault GCP Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/gcp)
- [GitHub OIDC with Vault](https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/about-security-hardening-with-openid-connect)
- **Related ADRs**: ADR-001 (Vault HA Deployment), ADR-002 (JSON Processing), ADR-004 (GitHub Actions Integration)
