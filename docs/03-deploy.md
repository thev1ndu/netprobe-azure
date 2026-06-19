# 03 — Running the Deploy Pipeline

Triggers `helm upgrade --install`, which upserts the storage secret and starts the
NetProbe pod or DaemonSet. The capture begins immediately on container start.

---

## Prerequisites

- [02-ado-setup.md](02-ado-setup.md) completed
- Image pushed to ACR (see [aks-node-tcpdump CI](https://github.com/thev1ndu/aks-node-tcpdump))
- ADO agent (jumphost `aks-jumphost`) is online — check **Project Settings → Agent pools → Default**

---

## Storage credentials — what you provide vs what the pipeline fetches

| Value | How it gets in |
|---|---|
| Storage account **name** | You enter it as the `storageAccountName` parameter at run time |
| Storage account **key** | Pipeline fetches it automatically via `az storage account keys list` using the ARM service connection — you never paste the key anywhere |

The key is injected into the `azure-storage-account-credentials-secret` Kubernetes secret on each run and is masked in all pipeline logs.

---

## How to run

1. Open **NetProbe — CD Deploy** → **Run pipeline**
2. Fill in the parameter form (all parameters described below)
3. Click **Run**

The pipeline will:
1. Apply the `azure-storage-account-credentials-secret` to the cluster using `$(storageAccountKey)` (secret pipeline variable set in ADO)
2. Download the `netprobe` Helm chart from GitHub releases
3. Run `helm upgrade --install` with the parameters you provided
4. Print pod status once Helm reports success

---

## Parameters reference

| Parameter | Required | Default | Description |
|---|---|---|---|
| `kubernetesServiceConnection` | no | `rnd-aks-thevindu` | Kubernetes Service Connection name |
| `storageAccountName` | yes | — | Azure Storage Account name (`sa18436`) |
| `namespace` | no | `kube-system` | Kubernetes namespace to deploy into |
| `deploymentMode` | no | `pod` | `pod` = pin to one node · `daemonset` = all nodes |
| `captureMode` | no | `tcpdump` | `tcpdump` = auto-start capture · `shell` = idle, use `kubectl exec` |
| `nodeName` | no | _(blank)_ | AKS node name to pin to in pod mode; blank lets the scheduler pick |
| `imageRegistry` | no | _(blank)_ | ACR login server (e.g. `acrrrrrrrr.azurecr.io`) — overrides the chart default |
| `imageDigest` | no | _(blank)_ | `sha256:...` digest — overrides the value baked into `values.yaml` |
| `shareName` | no | `fileshare` | Azure File Share name |
| `tcpdumpInterface` | no | `any` | Network interface to capture on (`any` \| `eth0`) |
| `tcpdumpRotateSeconds` | no | `300` | Rotate the `.pcap` output file every N seconds |
| `tcpdumpFilterHost` | no | _(blank)_ | BPF `host` filter (e.g. `10.0.0.1`) — blank captures all traffic |
| `tcpdumpFilePrefix` | no | `capture` | Prefix for `.pcap` filenames |
| `tcpdumpVerbose` | no | `false` | Print packets to stdout only — no `.pcap` file written |

---

## Invocation examples

### Capture all traffic on a specific node

```
storageAccountName:    sa18436
deploymentMode:        pod
releaseName:           debug-node-1
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpRotateSeconds:  300
```

### Capture traffic to a specific host

```
storageAccountName:    sa18436
deploymentMode:        pod
releaseName:           debug-apigw
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpFilterHost:     10.0.0.42
tcpdumpFilePrefix:     apigw-capture
tcpdumpRotateSeconds:  300
```

### Capture across all nodes simultaneously (DaemonSet)

```
storageAccountName:    sa18436
deploymentMode:        daemonset
releaseName:           netprobe-all-nodes
tcpdumpRotateSeconds:  300
```

Files from each node are named `capture-<hostname>-<timestamp>.pcap` — they never
overwrite each other on the share.

### Interactive shell — exec in to run tools manually

```
storageAccountName:    sa18436
captureMode:           shell
releaseName:           debug-shell
nodeName:              aks-aksnpuser-72792323-vmss00001m
```

Then exec into the pod (from the jumphost or any machine with kubectl access):

```bash
kubectl exec -it debug-shell -n kube-system -- /bin/bash

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

```bash
# Stream tcpdump output — pod mode
kubectl logs -f <releaseName> -n kube-system

# Stream from all nodes — DaemonSet mode
kubectl logs -l app.kubernetes.io/name=netprobe -n kube-system --prefix -f

# Pod status and node placement
kubectl get pod <releaseName> -n kube-system -o wide

# Confirm .pcap files are appearing on the share
az storage file list \
  --account-name sa18436 \
  --share-name fileshare \
  --path dumps \
  --output table
```

---

Next: [04-destroy.md](04-destroy.md) — download captures and tear down the pod.
