# 05 — Troubleshooting

---

## Deploy pipeline failures

| Symptom | Likely cause | Fix |
|---|---|---|
| Pipeline fails at **Fetch storage account key** | ARM Service Connection lacks permissions | Verify the service connection has at least **Contributor** on the resource group; check `az storage account keys list` runs manually |
| Pipeline fails at **Configure SSH** — `ssh-keyscan` times out | Jumpbox NSG blocks inbound SSH from ADO agent IPs | Ensure inbound TCP 22 is open on the jumpbox NSG from `0.0.0.0/0` or from ADO's agent IP ranges |
| Pipeline fails at **Configure SSH** — `Permission denied` | Wrong secure file uploaded, or key does not match jumpbox | Re-upload the correct private key as `jumpbox-ssh-key` in Pipelines → Library → Secure files |
| Pipeline fails at **Upsert storage secret** — `connection refused` | Jumpbox is stopped or unreachable | Start the jumpbox VM in the Azure portal; verify `ssh azureuser@<jumpbox-ip>` works |
| Pipeline fails at **Helm upgrade --install** — `helm: command not found` | Helm not installed on the jumpbox | SSH into the jumpbox and run: `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 \| bash` |
| Pipeline fails at **Helm upgrade --install** — `Error: chart "netprobe" not found` | Helm repo not yet published or URL wrong | Verify `https://thev1ndu.github.io/netprobe-helm` is accessible from the jumpbox: `curl -I https://thev1ndu.github.io/netprobe-helm/index.yaml` |
| Pipeline times out at Helm step | Pod stuck in `Pending` or `ContainerCreating` | Check pod events from jumpbox: `kubectl describe pod <releaseName> -n kube-system` |
| Pipeline fails immediately with **no permission** | Pipeline not authorized to use the secure file | Go to Pipelines → Library → Secure files → `key` → Authorize for all pipelines |

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
| `Error: release: not found` | `releaseName` does not match what was deployed | From jumpbox: `helm list -n kube-system` to find the exact release name |
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
| DaemonSet upgrade fails with immutable field error | Selector labels changed between releases | From jumpbox: `helm uninstall <name> -n kube-system` then re-deploy |

---

## Useful diagnostic commands

Run these from the jumpbox (`ssh azureuser@<jumpbox-ip>`):

```bash
# Full pod description including events
kubectl describe pod <releaseName> -n kube-system

# Storage secret contents (base64-decoded)
kubectl get secret azure-storage-account-credentials-secret \
  -n kube-system -o jsonpath='{.data.azurestorageaccountname}' | base64 -d

# Live pod logs
kubectl logs -f <releaseName> -n kube-system

# All netprobe resources in namespace
kubectl get all -l app.kubernetes.io/name=netprobe -n kube-system

# Helm release history
helm history <releaseName> -n kube-system
```
