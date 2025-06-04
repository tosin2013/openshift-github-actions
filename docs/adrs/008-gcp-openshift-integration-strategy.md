# ADR-008: GCP OpenShift Integration Strategy

**Status:** Proposed
**Date:** 2025-06-04
**Authors:** Tosin Akinosho, Sophia AI Assistant
**Reviewers:** Development Team

> **Note:** This ADR represents our current understanding and proposed approach. Implementation details may evolve based on research findings, testing results, and new discoveries during the development process. Any significant changes will be documented through ADR updates or new ADRs as appropriate.

## Context

Completing our multi-cloud strategy with our proven Vault HA deployment (95% success rate), AWS integration (ADR-006), and Azure integration (ADR-007), we need to establish a comprehensive approach for automated OpenShift 4.18 deployments on Google Cloud Platform (GCP) using GitHub Actions with dynamic credential management.

### Current State
- ✅ **Vault HA Foundation**: Production-ready with 95% success rate (ADR-001)
- ✅ **AWS Integration**: Defined strategy for AWS OpenShift deployment (ADR-006)
- ✅ **Azure Integration**: Defined strategy for Azure Red Hat OpenShift (ADR-007)
- ✅ **Dynamic Secrets Framework**: Zero-trust credential management (ADR-005)
- ✅ **GitHub Actions Architecture**: Workflow orchestration strategy (ADR-004)
- ⚠️ **GCP Integration Gap**: No GCP-specific deployment automation
- ⚠️ **IPI Deployment Gap**: No GCP Installer Provisioned Infrastructure automation

### GCP-Specific Requirements
1. **IPI Deployment**: Automated OpenShift 4.18 installation on GCP
2. **Dynamic GCP Credentials**: Just-in-time Service Account provisioning
3. **GCP Resource Management**: Complete GCP resource lifecycle
4. **GitHub Actions Integration**: Secure CI/CD workflow automation
5. **IAM Integration**: Google Cloud Identity and Access Management
6. **Compliance**: GCP security standards and governance

## Decision

Implement **GCP IPI Deployment with Dynamic Service Account Integration** using our Vault HA cluster:

### Architecture: GCP OpenShift Deployment Pipeline

```
┌─────────────────────────────────────────────────────────────┐
│                    GitHub Actions                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              GCP Deployment Workflow               │   │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐             │   │
│  │  │ Vault   │  │  GCP    │  │OpenShift│             │   │
│  │  │ Auth    │  │ Creds   │  │ Install │             │   │
│  │  └─────────┘  └─────────┘  └─────────┘             │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ JWT Authentication
                              │ Dynamic Service Account
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   Vault HA  │      │    GCP      │      │ OpenShift   │
│   Cluster   │      │ Resources   │      │  Cluster    │
│             │      │             │      │             │
│ GCP Secrets │----->│ • VPC       │----->│ • Masters   │
│ Engine      │      │ • Subnets   │      │ • Workers   │
│             │      │ • Firewall  │      │ • Ingress   │
│             │      │ • IAM       │      │ • Storage   │
│             │      │ • Service   │      │ • Registry  │
│             │      │   Account   │      │             │
└─────────────┘      └─────────────┘      └─────────────┘
```

### Core Integration Strategy

#### 1. **GCP Secrets Engine Configuration**
```hcl
# Enable GCP secrets engine in Vault
vault secrets enable -path=gcp gcp

# Configure GCP secrets engine with Service Account
vault write gcp/config \
  credentials=@gcp-vault-admin-key.json

# Create roleset for OpenShift installation
vault write gcp/roleset/openshift-installer \
  project="$GCP_PROJECT_ID" \
  bindings='[
    {
      "resource": "//cloudresourcemanager.googleapis.com/projects/'$GCP_PROJECT_ID'",
      "roles": [
        "roles/compute.admin",
        "roles/iam.serviceAccountAdmin",
        "roles/iam.serviceAccountKeyAdmin",
        "roles/iam.serviceAccountUser",
        "roles/iam.securityAdmin",
        "roles/storage.admin",
        "roles/dns.admin"
      ]
    }
  ]' \
  token_scopes="https://www.googleapis.com/auth/cloud-platform"
```

#### 2. **GCP IAM Permissions for OpenShift IPI**
```json
{
  "required_roles": [
    "roles/compute.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountKeyAdmin",
    "roles/iam.serviceAccountUser",
    "roles/iam.securityAdmin",
    "roles/storage.admin",
    "roles/dns.admin",
    "roles/compute.loadBalancerAdmin",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin"
  ],
  "required_apis": [
    "compute.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "servicemanagement.googleapis.com",
    "serviceusage.googleapis.com",
    "storage-api.googleapis.com",
    "storage-component.googleapis.com"
  ]
}
```

## Consequences

### Positive
- **GCP Native Integration**: Leverages Google Cloud's robust infrastructure
- **Global Network**: Google's high-performance global network
- **Cost Optimization**: Sustained use discounts and preemptible instances
- **Innovation**: Access to Google's latest cloud technologies
- **Security**: Dynamic Service Account credentials with short TTL
- **Scalability**: Auto-scaling capabilities and global load balancing
- **Compliance**: GCP compliance certifications and security features

### Negative
- **GCP Dependency**: Requires GCP project and appropriate quotas
- **Complexity**: Multi-step workflow with GCP-specific configurations
- **Learning Curve**: Team needs GCP and OpenShift expertise
- **Regional Limitations**: Some GCP services not available in all regions

### Neutral
- **Cost Considerations**: Need to monitor and optimize GCP spending
- **Vendor Diversity**: Adds third cloud provider to manage
- **Integration Complexity**: Additional integration points to maintain

## Implementation

### Phase 1: GCP Secrets Engine Setup (Week 1)
1. **Configure GCP Secrets Engine**
   ```bash
   # Enable GCP secrets engine
   vault secrets enable -path=gcp gcp

   # Configure with Service Account
   vault write gcp/config credentials=@gcp-vault-admin-key.json

   # Create OpenShift installer roleset
   vault write gcp/roleset/openshift-installer \
     project="$GCP_PROJECT_ID" \
     bindings=@gcp-openshift-bindings.json
   ```

2. **Test Dynamic Credential Generation**
   ```bash
   # Test credential generation
   vault read gcp/key/openshift-installer

   # Verify credentials work
   gcloud auth activate-service-account --key-file=sa-key.json
   gcloud projects list
   ```

### Success Metrics
- **Deployment Success Rate**: 95% (matching Vault HA success)
- **Deployment Time**: < 45 minutes for complete cluster
- **Security Compliance**: Zero long-lived credentials
- **Cost Optimization**: Automated resource rightsizing

## References

- [OpenShift IPI on GCP Documentation](https://docs.openshift.com/container-platform/4.18/installing/installing_gcp/installing-gcp-default.html)
- [Vault GCP Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/gcp)
- [GCP IAM Best Practices](https://cloud.google.com/iam/docs/using-iam-securely)
- [GitHub Actions with GCP](https://github.com/google-github-actions)
- **Related ADRs**: ADR-003 (Multi-Cloud Integration), ADR-005 (Dynamic Secrets), ADR-006 (AWS Integration), ADR-007 (Azure Integration)