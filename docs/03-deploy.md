# 03 — Running the Deploy Pipeline

Triggers `helm upgrade --install`, which upserts the storage secret and starts the
NetProbe pod or DaemonSet on the AKS cluster via VMSS run-command.

---

## Prerequisites

- [02-ado-setup.md](02-ado-setup.md) completed
- `is-vmss` instance `0` is running and has kubectl/helm installed
- Image pushed to ACR (see [aks-node-tcpdump CI](https://github.com/thev1ndu/aks-node-tcpdump))

---

## How it works

All cluster operations run **inside `is-vmss`** via `az vmss run-command invoke`.
The ADO pipeline (Microsoft-hosted `ubuntu-latest`) uses the ARM SC (`thevindu-rnd-sc`)
to send commands through the Azure control plane — no SSH, no public IP required.

```
ADO hosted agent
  └─ AzureCLI@2 (thevindu-rnd-sc)
       └─ az vmss run-command invoke → is-vmss (inside VNet)
            └─ kubectl / helm → aks-wso2is (private API server)
```

---

## How to run

1. Open **NetProbe — CD Deploy** → **Run pipeline**
2. Fill in the parameter form
3. Click **Run**

The pipeline will:
1. Fetch the storage account key via ARM SC and mask it as a secret
2. Run `kubectl apply` on `is-vmss` to upsert `azure-storage-account-credentials-secret`
3. Run `helm upgrade --install netprobe` on `is-vmss` with the parameters you provided
4. Print pod status from `is-vmss`

---

## Parameters reference

| Parameter | Required | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | no | `thevindu-rnd-sc` | ARM Service Connection name |
| `vmssResourceGroup` | no | `rg-thevindu` | Resource group containing `is-vmss` |
| `vmssName` | no | `is-vmss` | VMSS name |
| `vmssInstanceId` | no | `0` | VMSS instance ID to run commands on |
| `storageAccountName` | no | `sa18436` | Azure Storage Account name |
| `namespace` | no | `kube-system` | Kubernetes namespace to deploy into |
| `deploymentMode` | no | `pod` | `pod` = pin to one node · `daemonset` = all nodes |
| `captureMode` | no | `tcpdump` | `tcpdump` = auto-start capture · `shell` = idle, use `kubectl exec` |
| `nodeName` | no | _(blank)_ | AKS node name to pin to in pod mode; blank lets scheduler pick |
| `imageRegistry` | no | _(blank)_ | ACR login server (e.g. `acrrrrrrrr.azurecr.io`) |
| `imageDigest` | no | _(blank)_ | `sha256:...` digest — overrides the value baked into the chart |
| `shareName` | no | `fileshare` | Azure File Share name |
| `tcpdumpInterface` | no | `any` | Network interface (`any` \| `eth0`) |
| `tcpdumpRotateSeconds` | no | `300` | Rotate the `.pcap` file every N seconds |
| `tcpdumpFilterHost` | no | _(blank)_ | BPF `host` filter (e.g. `10.0.0.1`) — blank captures all traffic |
| `tcpdumpFilePrefix` | no | `capture` | Prefix for `.pcap` filenames |
| `tcpdumpVerbose` | no | `false` | Print packets to stdout only — no `.pcap` file written |

All parameters have defaults — a minimal run needs no changes at all.

---

## Invocation examples

### Capture all traffic on a specific node

```
deploymentMode:        pod
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpRotateSeconds:  300
```

### Capture traffic to a specific host

```
deploymentMode:        pod
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpFilterHost:     10.0.0.42
tcpdumpFilePrefix:     apigw-capture
tcpdumpRotateSeconds:  300
```

### Capture across all nodes simultaneously (DaemonSet)

```
deploymentMode:        daemonset
tcpdumpRotateSeconds:  300
```

Files from each node are named `capture-<hostname>-<timestamp>.pcap` — they never
overwrite each other on the share.

### Interactive shell — exec in to run tools manually

```
captureMode:           shell
nodeName:              aks-aksnpuser-72792323-vmss00001m
```

Then exec into the pod from `is-vmss` (or any host with kubectl access):

```bash
kubectl exec -it netprobe -n kube-system -- /bin/bash

# Available tools inside the container:
ss -tnp                                          # active TCP connections
netstat -tlnp                                    # listening ports
dig apigw.example.com                            # DNS resolution check
nc -zv apigw.example.com 443                     # TCP port reachability
openssl s_client -connect apigw.example.com:443  # TLS certificate inspection
mtr --report apigw.example.com                   # path trace with latency
tshark -r /mnt/fileshare/dumps/capture.pcap      # inspect existing .pcap on share
```

---

## Post-deploy checks

Run these from `is-vmss` or the jumphost:

```bash
# Stream tcpdump output — pod mode
kubectl logs -f netprobe -n kube-system

# Stream from all nodes — DaemonSet mode
kubectl logs -l app.kubernetes.io/name=netprobe -n kube-system --prefix -f

# Pod status and node placement
kubectl get pod netprobe -n kube-system -o wide

# Confirm .pcap files are appearing on the share
az storage file list \
  --account-name sa18436 \
  --share-name fileshare \
  --path dumps \
  --output table
```

---

Next: [04-destroy.md](04-destroy.md) — download captures and tear down the pod.
