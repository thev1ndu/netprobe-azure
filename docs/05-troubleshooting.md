# 05 — Troubleshooting

---

## Deploy pipeline failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Pipeline fails at **Fetch storage account key** | ARM Service Connection lacks permissions | Verify the service principal has at least **Contributor** on the resource group; try `az storage account keys list` manually with the same credentials |
| Pipeline fails at **Upsert storage secret** — `AuthorizationFailed` | Service principal lacks `Virtual Machine Contributor` on the VMSS | `az role assignment create --assignee <sp-id> --role "Virtual Machine Contributor" --scope <vmss-id>` |
| Pipeline fails at **Upsert storage secret** — `VMAgentStatusCommunicationError` | VMSS instance is stopped or the VM agent is unresponsive | Start the VMSS instance in the portal; verify the Azure VM Agent is running: `az vmss get-instance-view --resource-group <rg> --name <vmss> --instance-id 0` |
| Pipeline fails at **Helm upgrade --install** — `helm: command not found` | Helm not installed on the jumpbox instance | Run via `az vmss run-command invoke`: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| Pipeline fails at **Helm upgrade --install** — `Error: chart "netprobe" not found` | Helm chart URL unreachable from the jumpbox | Verify outbound HTTPS from the jumpbox: `az vmss run-command invoke --scripts "curl -I https://thev1ndu.github.io/netprobe-helm/index.yaml"` |
| Pipeline fails at **Helm upgrade --install** — `kubectl: command not found` | kubectl not installed on the jumpbox instance | Run via run-command: `az aks install-cli` or install manually |
| Pipeline fails at **Helm upgrade --install** — `dial tcp: i/o timeout` | Jumpbox cannot reach the AKS private API server | See [Network / connectivity](#network--connectivity) below |
| Pipeline times out at Helm step | Pod stuck in `Pending` or `ContainerCreating` | Check pod events via run-command: `kubectl describe pod <releaseName> -n kube-system` |

---

## Network / connectivity

### Does the jumpbox need to be in the same subnet as AKS?

**No — same VNet is sufficient.** The AKS private API server is a private endpoint whose IP is accessible from any subnet in the VNet. The private DNS zone (`privatelink.<region>.azmk8s.io`) is linked at the VNet level, so all subnets resolve the API server hostname correctly.

`az vmss run-command invoke` itself goes through the Azure control plane (ARM API) and has no VNet or subnet requirements.

### Jumpbox cannot reach the AKS private API server

Verify connectivity via run-command:

```bash
az vmss run-command invoke \
  --resource-group <vmss-rg> \
  --name <vmss-name> \
  --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl cluster-info"
```

If this fails with a timeout, check:

1. **The jumpbox is in the same VNet as AKS** — a different VNet requires VNet peering with the private DNS zone also linked to the peered VNet.

2. **The jumpbox subnet NSG allows outbound TCP 443 to the AKS API server private IP:**

```bash
# Find the AKS private API server IP
az network private-endpoint list \
  --resource-group <aks-rg> \
  --query "[?contains(name,'aks')].customDnsConfigs[0].ipAddresses[0]" \
  -o tsv

# Check outbound NSG rules on the jumpbox subnet
az network nsg rule list \
  --resource-group <vmss-rg> \
  --nsg-name <jumpbox-nsg> \
  --query "[?direction=='Outbound'].{name:name,priority:priority,access:access,destPort:destinationPortRange}" \
  -o table
```

If port 443 to the AKS IP is denied, add a rule:

```bash
az network nsg rule create \
  --resource-group <vmss-rg> \
  --nsg-name <jumpbox-nsg> \
  --name Allow-AKS-API-443 \
  --priority 200 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes <aks-api-private-ip> \
  --destination-port-ranges 443
```

3. **The kubeconfig on the jumpbox is pointing to the private API server FQDN** (not a public endpoint). Check: `kubectl config view --minify` — the server URL should resolve to an RFC 1918 IP.

---

## Pod failures after deploy

| Symptom | Likely cause | Fix |
|---|---|---|
| Pod stuck in `ContainerCreating` | Storage secret missing or keys incorrect | `kubectl get secret azure-storage-account-credentials-secret -n kube-system -o yaml` — verify both keys are present and non-empty |
| Pod stuck in `ContainerCreating` | `dumps/` directory does not exist on the share | `az storage directory create --account-name <sa> --share-name fileshare --name dumps` |
| Pod stuck in `Pending` | `nodeName` typo, or node is not Ready | `kubectl describe pod <releaseName> -n kube-system` → check Events section |
| `ImagePullBackOff` | AKS cannot pull from ACR | Verify AcrPull role: `az role assignment list --assignee <kubelet-client-id> --query "[].roleDefinitionName"` |
| `ImagePullBackOff` | Wrong image registry or digest in values / pipeline parameter | Check `image.registry` and `image.digest` passed as overrides |
| `permission denied` writing `.pcap` | Container not running privileged | Verify `securityContext.privileged: true` in `charts/netprobe/values.yaml` |
| No `.pcap` files appear on share after several minutes | `captureMode` set to `shell` | Check the pipeline parameter — `tcpdump` mode is required for auto-capture |

---

## Destroy pipeline failures

| Symptom | Likely cause | Fix |
|---|---|---|
| `Error: release: not found` | `releaseName` does not match what was deployed | Run via run-command: `helm list -n kube-system` to find the exact release name |
| Pod still visible after destroy succeeds | Pod is in terminating grace period | Wait ~30 s and re-check; it will clear |
| DaemonSet pods linger | Each node terminates its pod independently | Re-check after ~60 s; all should clear |

---

## Storage / share issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `az storage file list` returns empty | Wrong share name or path | Confirm `--share-name` matches `SHARE_NAME`, and `--path dumps` exists |
| Share quota full | Long capture or many nodes filling 5 GiB | `az storage share update --quota 20 --name fileshare --account-name <sa>` |
| Can't mount share in pod | SMB port 445 blocked by NSG | Ensure outbound TCP 445 is allowed from AKS node subnet to the storage account endpoint |

---

## Helm chart issues

| Symptom | Likely cause | Fix |
|---|---|---|
| `helm upgrade` creates both Pod and DaemonSet | `deploymentMode` parameter not passed correctly | Confirm the Helm override `deploymentMode=pod` or `deploymentMode=daemonset` is in the overrides string |
| DaemonSet upgrade fails with immutable field error | Selector labels changed between releases | Run via run-command: `helm uninstall <name> -n kube-system` then re-deploy |

---

## Useful diagnostic commands

Run these via `az vmss run-command invoke` (requires ARM credentials and `Virtual Machine Contributor` on the VMSS):

```bash
# Full pod description including events
az vmss run-command invoke \
  --resource-group <vmss-rg> --name <vmss-name> --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl describe pod <releaseName> -n kube-system"

# Storage secret contents (base64-decoded)
az vmss run-command invoke \
  --resource-group <vmss-rg> --name <vmss-name> --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl get secret azure-storage-account-credentials-secret \
    -n kube-system -o jsonpath='{.data.azurestorageaccountname}' | base64 -d"

# Live pod logs (run-command streams full output on completion)
az vmss run-command invoke \
  --resource-group <vmss-rg> --name <vmss-name> --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl logs <releaseName> -n kube-system --tail=100"

# All netprobe resources in namespace
az vmss run-command invoke \
  --resource-group <vmss-rg> --name <vmss-name> --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl get all -l app.kubernetes.io/name=netprobe -n kube-system"

# Helm release history
az vmss run-command invoke \
  --resource-group <vmss-rg> --name <vmss-name> --instance-id 0 \
  --command-id RunShellScript \
  --scripts "helm history <releaseName> -n kube-system"
```
