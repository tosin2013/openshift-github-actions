# Troubleshooting Guide for OpenShift Multi-Cloud Automation

This guide provides solutions for common issues encountered when deploying OpenShift 4.18 across multiple cloud platforms using GitHub Actions and HashiCorp Vault.

## Common Issues and Solutions

### 1. GitHub Actions Authentication Issues

#### Problem: Vault Authentication Fails
```
Error: failed to authenticate to Vault: permission denied
```

**Solutions:**
1. **Check Vault JWT Configuration**
   ```bash
   vault read auth/jwt/config
   vault read auth/jwt/role/github-actions-role
   ```

2. **Verify GitHub Repository Settings**
   - Ensure `VAULT_URL`, `VAULT_JWT_AUDIENCE`, and `VAULT_ROLE` secrets are set
   - Check that the repository URL matches the Vault role configuration

3. **Validate JWT Token**
   - Ensure the workflow is running from the correct branch
   - Check that the repository has the correct permissions

#### Problem: GitHub Secrets Not Found
```
Error: Secret VAULT_URL not found
```

**Solutions:**
1. **Add Missing Secrets**
   - Go to Repository Settings > Secrets and variables > Actions
   - Add required secrets: `VAULT_URL`, `VAULT_JWT_AUDIENCE`, `VAULT_ROLE`

2. **Check Secret Names**
   - Ensure secret names match exactly (case-sensitive)
   - Verify no extra spaces or characters

### 2. Cloud Provider Authentication Issues

#### AWS Authentication Problems

**Problem: AWS Credentials Invalid**
```
Error: The security token included in the request is invalid
```

**Solutions:**
1. **Check Vault AWS Configuration**
   ```bash
   vault read aws/config/root
   vault read aws/roles/openshift-installer
   ```

2. **Verify AWS Permissions**
   - Ensure the AWS user has sufficient permissions for OpenShift installation
   - Check IAM policies and roles

3. **Test Credential Generation**
   ```bash
   vault read aws/creds/openshift-installer
   ```

#### Azure Authentication Problems

**Problem: Azure Service Principal Invalid**
```
Error: AADSTS70002: Error validating credentials
```

**Solutions:**
1. **Check Vault Azure Configuration**
   ```bash
   vault read azure/config
   vault read azure/roles/openshift-installer
   ```

2. **Verify Service Principal**
   - Ensure client ID, client secret, and tenant ID are correct
   - Check service principal permissions

3. **Test Credential Generation**
   ```bash
   vault read azure/creds/openshift-installer
   ```

#### GCP Authentication Problems

**Problem: GCP Service Account Invalid**
```
Error: Request had invalid authentication credentials
```

**Solutions:**
1. **Check Vault GCP Configuration**
   ```bash
   vault read gcp/config
   vault read gcp/roleset/openshift-installer
   ```

2. **Verify Service Account**
   - Ensure service account key is valid and not expired
   - Check service account permissions

3. **Test Key Generation**
   ```bash
   vault read gcp/key/openshift-installer
   ```

### 3. OpenShift Installation Issues

#### Problem: Installation Timeout
```
Error: context deadline exceeded
```

**Solutions:**
1. **Check Cloud Provider Quotas**
   - Verify sufficient compute, storage, and network quotas
   - Request quota increases if needed

2. **Review Installation Logs**
   ```bash
   tail -f installation-dir/.openshift_install.log
   ```

3. **Check Network Connectivity**
   - Ensure internet access for downloading images
   - Verify DNS resolution

#### Problem: DNS Resolution Issues
```
Error: failed to resolve DNS name
```

**Solutions:**
1. **Verify Domain Configuration**
   - Ensure base domain is properly configured
   - Check DNS zone delegation

2. **Check Cloud Provider DNS**
   - AWS: Verify Route 53 hosted zone
   - Azure: Check DNS zone configuration
   - GCP: Verify Cloud DNS setup

#### Problem: Insufficient Resources
```
Error: insufficient capacity
```

**Solutions:**
1. **Check Instance/VM Availability**
   - Try different instance types or sizes
   - Use different availability zones/regions

2. **Review Resource Requirements**
   - Ensure minimum requirements are met
   - Consider reducing cluster size for testing

### 4. Network and Connectivity Issues

#### Problem: Cluster Nodes Not Ready
```
Error: nodes are not ready
```

**Solutions:**
1. **Check Node Status**
   ```bash
   oc get nodes -o wide
   oc describe node <node-name>
   ```

2. **Review Network Configuration**
   - Verify security groups/firewall rules
   - Check subnet configurations

3. **Examine Pod Network**
   ```bash
   oc get pods -n openshift-sdn
   oc logs -n openshift-sdn <sdn-pod>
   ```

#### Problem: Load Balancer Issues
```
Error: load balancer not accessible
```

**Solutions:**
1. **Check Load Balancer Status**
   - AWS: Check ELB/ALB status
   - Azure: Check Load Balancer configuration
   - GCP: Check Load Balancer health

2. **Verify Security Groups**
   - Ensure proper ingress/egress rules
   - Check port configurations

### 5. Storage Issues

#### Problem: Storage Class Not Available
```
Error: no default storage class
```

**Solutions:**
1. **Check Storage Classes**
   ```bash
   oc get storageclass
   ```

2. **Configure Default Storage Class**
   ```bash
   oc patch storageclass <storage-class-name> -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
   ```

3. **Provider-Specific Solutions**
   - AWS: Ensure EBS CSI driver is installed
   - Azure: Check Azure Disk CSI driver
   - GCP: Verify GCE Persistent Disk CSI driver

### 6. Vault-Related Issues

#### Problem: Secret Not Found in Vault
```
Error: secret not found at path
```

**Solutions:**
1. **Check Secret Path**
   ```bash
   vault kv list secret/openshift/
   vault kv get secret/openshift/pull-secret
   ```

2. **Verify Permissions**
   ```bash
   vault policy read openshift-deployment
   ```

3. **Re-store Secrets**
   ```bash
   vault kv put secret/openshift/pull-secret pullSecret='...'
   ```

#### Problem: Vault Connection Issues
```
Error: connection refused
```

**Solutions:**
1. **Check Vault Status**
   ```bash
   vault status
   ```

2. **Verify Network Connectivity**
   - Check firewall rules
   - Verify Vault URL is accessible

3. **Check Vault Seal Status**
   ```bash
   vault operator unseal
   ```

## Debugging Commands

### General Debugging
```bash
# Check cluster status
oc get clusterversion
oc get clusteroperators
oc get nodes

# Check critical pods
oc get pods -n openshift-etcd
oc get pods -n openshift-kube-apiserver
oc get pods -n openshift-kube-controller-manager

# Check events
oc get events --sort-by='.lastTimestamp'
```

### Network Debugging
```bash
# Check network operator
oc get network.operator cluster -o yaml
oc get network.config cluster -o yaml

# Check DNS
oc get pods -n openshift-dns
nslookup kubernetes.default.svc.cluster.local
```

### Storage Debugging
```bash
# Check storage operator
oc get clusteroperator storage
oc get storageclass
oc get pv
oc get pvc --all-namespaces
```

## Log Collection

### Gather Cluster Information
```bash
# Use must-gather for comprehensive logs
oc adm must-gather

# Specific component logs
oc logs -n openshift-kube-apiserver <pod-name>
oc logs -n openshift-etcd <pod-name>
```

### Installation Logs
```bash
# OpenShift installer logs
tail -f installation-dir/.openshift_install.log

# Terraform logs (if using UPI)
export TF_LOG=DEBUG
terraform apply
```

## Recovery Procedures

### Cluster Recovery
1. **Backup etcd** (if cluster is partially functional)
   ```bash
   oc get etcdbackup -n openshift-etcd
   ```

2. **Node Recovery**
   ```bash
   # Drain and delete problematic node
   oc drain <node-name> --ignore-daemonsets --delete-emptydir-data
   oc delete node <node-name>
   ```

3. **Operator Recovery**
   ```bash
   # Restart operator
   oc delete pod -n <operator-namespace> <operator-pod>
   ```

### Complete Cluster Rebuild
If recovery is not possible:
1. Run the destroy workflow
2. Clean up any remaining resources
3. Deploy a new cluster

## Getting Help

### Internal Resources
1. Check installation logs in GitHub Actions artifacts
2. Review Vault audit logs
3. Examine cloud provider console for resource status

### External Resources
1. [Red Hat OpenShift Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18)
2. [OpenShift Troubleshooting Guide](https://docs.redhat.com/en/documentation/openshift_container_platform/4.18/html/support/troubleshooting)
3. [HashiCorp Vault Documentation](https://developer.hashicorp.com/vault/docs)

### Support Channels
1. Red Hat Support (for OpenShift issues)
2. Cloud provider support (for infrastructure issues)
3. HashiCorp Support (for Vault issues)

---

**Remember**: Always check the GitHub Actions workflow logs first, as they often contain the most relevant error information for troubleshooting deployment issues.
