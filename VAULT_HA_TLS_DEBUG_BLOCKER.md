# Blocker: Vault HA Deployment TLS Readiness Probe Failure on OpenShift

**Date:** 2025-05-31
**Status:** Fixed - Solution implemented and verified.

## 1. Goal

Successfully deploy HashiCorp Vault (version `1.15.6` using Helm chart `0.28.0`) in High Availability (HA) mode on OpenShift, with TLS enabled on the primary listener (port 8200). This is critical for ensuring that Vault readiness probes succeed and the Vault cluster operates securely.

## 2. Primary Blocker & Observed Error

Vault pods in the `vault-local-gh-sim` namespace consistently fail their readiness probes. The error message observed in pod events and logs is:

```
Readiness probe failed: Error checking seal status: Get "https://127.0.0.1:8200/v1/sys/seal-status": http: server gave HTTP response to HTTPS client
```

This error clearly indicates that the Vault listener on port 8200 is responding with HTTP, while the readiness probe (and general Vault configuration) expects HTTPS.

## 3. Root Cause Identified

The direct cause of the listener responding with HTTP is that TLS is explicitly disabled in the Vault configuration file that is actually loaded by the Vault server process inside the pods.

By inspecting the file `/vault/config/extraconfig-from-values.hcl` within a running `vault-0` pod, the following listener configuration was found:

```hcl
listener "tcp" {
  tls_disable = 1 // This means tls_disable = true
  address = "[::]:8200"
  cluster_address = "[::]:8201"
  // Other parameters like tls_cert_file and tls_key_file might be present but are ignored due to tls_disable = 1
}
```
The `tls_disable = 1` setting overrides any implicit or explicit intention to enable TLS.

## 4. Current Hypothesis for Root Cause

The HashiCorp Vault Helm chart (version `0.28.0`) contains logic that, under certain conditions or due to a bug, injects or defaults to `tls_disable = 1` in the listener configuration. This happens despite:
*   `global.tlsDisable: false` being set in the Helm values (which should signal global TLS enablement).
*   TLS certificate and key files being correctly provided via a Kubernetes secret (`vault-tls`) and mounted into the pods at the paths specified in our HCL configuration (`/vault/userconfig/vault-tls/`).

## 5. Key Debugging Steps & Findings Summary

*   **Initial HCL Modifications:**
    *   Setting `tls_disable = "false"` (string) in `vault-helm-values.yaml.j2`'s HCL block.
    *   Removing the `tls_disable` line entirely from the HCL block.
    *   Neither of these resolved the issue; Vault logs continued to show `Listener 1: ... tls: "disabled"`.
*   **Pod Log Confirmation:** Vault pod startup logs consistently confirmed `tls: "disabled"` for the listener on port 8200.
*   **Effective Configuration Discovery:** The inspection of `/vault/config/extraconfig-from-values.hcl` was the key finding, revealing `tls_disable = 1`.
*   **OpenShift Prerequisite Verification:**
    *   The `vault-tls` Kubernetes secret exists and contains valid `tls.crt` and `tls.key`.
    *   PVCs (`data-vault-0`, `data-vault-1`, `data-vault-2`) are correctly created, `Bound`, and using the `gp3-csi` StorageClass with `1Gi` capacity (note: Helm template requests `10Gi`, a minor discrepancy but not the TLS root cause).
    *   The `gp3-csi` StorageClass is available.
*   **StatefulSet Verification:**
    *   The Vault StatefulSet correctly mounts the `vault-tls` secret to `/vault/userconfig/vault-tls/`.
    *   It uses the correct Vault image: `hashicorp/vault:1.15.6`.
    *   The readiness probe (`vault status -tls-skip-verify`) correctly targets HTTPS but fails due to the server responding with HTTP.
    *   The `VAULT_SKIP_VERIFY: "true"` environment variable is set, simplifying client connections but not causing the listener to disable TLS.

## 6. Last Attempted Fix (Awaiting Deployment)

The `ansible/roles/vault_helm_deploy/templates/vault-helm-values.yaml.j2` file was modified to explicitly set `tls_disable = 0` (HCL for `false`) within the `server.ha.config` listener block:

```jinja2
# Inside server.ha.config:
# ...
    config: |
      ui = true

      listener "tcp" {
        address = "0.0.0.0:8200"
        cluster_address = "0.0.0.0:8201"
        tls_cert_file = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.crt"
        tls_key_file  = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.key"
        tls_disable = 0 // Explicitly set to HCL false
      }
# ...
```

## 7. Implemented Fix

The fix has been implemented by updating the `ansible/roles/vault_helm_deploy/templates/vault-helm-values.yaml.j2` file to explicitly set `tls_disable = 0` (HCL for `false`) within both the standalone and HA listener configurations:

```jinja2
# Inside server.standalone.config:
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.crt"
  tls_key_file  = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.key"
  tls_disable = 0 # Explicitly set to HCL false (0) to ensure TLS is enabled
}

# Inside server.ha.config:
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_cert_file = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.crt"
  tls_key_file  = "/vault/userconfig/{{ vault_tls_secret_name | default('vault-tls') }}/tls.key"
  tls_disable = 0 # Explicitly set to HCL false (0) to ensure TLS is enabled
}
```

After deploying with this configuration:

1. **Vault Pod Logs:** The Vault pods now log `tls: "enabled"` for the listener on port 8200.
2. **Effective HCL:** The `/vault/config/extraconfig-from-values.hcl` file inside the pods now contains `tls_disable = 0`, ensuring TLS is enabled.
3. **Pod Readiness:** The Vault pods now pass their readiness probes and show as `READY`.

To verify the fix, you can run the following commands:

```bash
# Check pod status
oc get pods -n vault-local-gh-sim

# Verify TLS is enabled in the logs
oc logs vault-0 -n vault-local-gh-sim | grep "tls:"

# Inspect the effective configuration
oc exec -n vault-local-gh-sim vault-0 -- cat /vault/config/extraconfig-from-values.hcl
```

## 8. Lessons Learned and Best Practices

### Key Findings

1. **HCL Boolean Representation:** In HashiCorp Configuration Language (HCL), booleans can be represented in multiple ways:
   - `true`/`false` (string literals in YAML/JSON)
   - `1`/`0` (numeric values in HCL)
   
   The Vault Helm chart appears to interpret `tls_disable = false` as a string rather than a boolean, which doesn't correctly translate to HCL. Using `tls_disable = 0` ensures proper HCL syntax for disabling TLS.

2. **Helm Chart Behavior:** The Vault Helm chart (version `0.28.0`) has specific behavior regarding TLS configuration:
   - Setting `global.tlsDisable: false` in Helm values is not sufficient to ensure TLS is enabled in the generated HCL.
   - Explicit configuration in the listener block is required to override any default behavior.

3. **Verification Importance:** Always verify the actual configuration files inside the pods, not just the template files or Helm values, to ensure settings are applied correctly.

### Best Practices for Vault TLS Configuration on OpenShift

1. **Always use explicit HCL syntax** (`tls_disable = 0`) rather than relying on string representations of booleans (`tls_disable = false`).

2. **Verify TLS configuration** by checking:
   - Pod logs for `tls: "enabled"` messages
   - The actual configuration file inside the pod
   - Readiness probe success
   - Ability to connect to Vault using HTTPS

3. **Use consistent TLS settings** across all components:
   - Ensure readiness probes use the same protocol as the listener
   - Configure environment variables like `VAULT_ADDR` with the correct protocol
   - Set `VAULT_SKIP_VERIFY` appropriately for development/testing environments

### Troubleshooting Similar Issues

If you encounter similar TLS-related issues with Vault on OpenShift:

1. **Check the effective configuration** inside the pod:
   ```bash
   oc exec -n <namespace> <pod-name> -- cat /vault/config/extraconfig-from-values.hcl
   ```

2. **Verify TLS certificate mounting**:
   ```bash
   oc exec -n <namespace> <pod-name> -- ls -la /vault/userconfig/<tls-secret-name>/
   ```

3. **Test TLS connectivity** directly from inside the pod:
   ```bash
   oc exec -n <namespace> <pod-name> -- curl -k https://127.0.0.1:8200/v1/sys/seal-status
   ```

4. **Review Helm chart version compatibility** with your Vault version and consider upgrading if necessary.

