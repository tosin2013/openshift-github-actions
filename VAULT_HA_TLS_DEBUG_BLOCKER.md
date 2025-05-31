# Blocker: Vault HA Deployment TLS Readiness Probe Failure on OpenShift

**Date:** 2025-05-31
**Status:** Blocked - Awaiting deployment of latest configuration change.

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

## 7. Immediate Next Step (Currently Blocked/Pending by User)

The crucial next step is to **deploy this latest configuration change** by running the `./run_local_vault_deploy.sh` script. After deployment:

1.  **Verify Vault Pod Logs:** Check if the Vault pods (e.g., `vault-0`) now log `tls: "enabled"` for the listener on port 8200.
    ```bash
    oc logs vault-0 -n vault-local-gh-sim
    ```
2.  **Inspect Effective HCL:** Re-inspect `/vault/config/extraconfig-from-values.hcl` inside a pod to confirm that `tls_disable = 0` (or that `tls_disable` is absent and TLS is enabled by default due to certs).
    ```bash
    oc exec -n vault-local-gh-sim vault-0 -- cat /vault/config/extraconfig-from-values.hcl
    ```
3.  **Check Pod Readiness:** Observe if the Vault pods become `READY` (i.e., pass their readiness probes).
    ```bash
    oc get pods -n vault-local-gh-sim -w
    ```

## 8. Potential Further Investigation (If `tls_disable = 0` Fails)

*   **Helm Chart Source Code:** If the explicit `tls_disable = 0` does not work, a deep dive into the Vault Helm chart (version `0.28.0`) template files (e.g., `templates/server-config-configmap.yaml`, `_helpers.tpl`) will be necessary to understand how the `extraconfig-from-values.hcl` content is generated, particularly how `global.tlsDisable` and `server.ha.config` interact to influence the listener's `tls_disable` HCL property.
*   **Helm Chart Version:** Consider testing with a slightly newer or older patch version of the Vault Helm chart if a bug in version `0.28.0` is strongly suspected.
*   **Alternative HCL Structure:** Experiment with providing the `tls_cert_file` and `tls_key_file` directly under `server.ha.listener` in the Helm values, if the chart supports this, rather than embedding them in the raw HCL `server.ha.config`.

