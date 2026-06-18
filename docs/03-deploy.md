# 03 — Running the Deploy Pipeline

Triggers `helm upgrade --install`, which upserts the storage secret and starts the
NetProbe pod or DaemonSet. The capture begins immediately on container start.

---

## Prerequisites

- [02-ado-setup.md](02-ado-setup.md) completed
- Image pushed to ACR (see [aks-node-tcpdump CI](https://github.com/thev1ndu/aks-node-tcpdump))
- Jumpbox has outbound HTTPS to `thev1ndu.github.io` (helm chart is pulled from there at deploy time)

---

## How to run

1. Open **NetProbe — CD Deploy** → **Run pipeline**
2. Fill in the parameter form (all parameters described below)
3. Click **Run**

The pipeline will:
1. Download the jumpbox SSH key from ADO Library and configure SSH
2. Fetch the storage account key via the ARM service connection
3. Upsert the `azure-storage-account-credentials-secret` in the target namespace (via jumpbox)
4. Pull the `netprobe` helm chart from `https://thev1ndu.github.io/netprobe-helm` on the jumpbox
5. Run `helm upgrade --install` on the jumpbox with the parameters you provided
6. Print pod status once Helm reports success

---

## Parameters reference

| Parameter | Required | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | yes | — | ARM Service Connection name from step 1 of ADO setup |
| `aksResourceGroup` | yes | — | Azure resource group containing the AKS cluster and storage account |
| `jumpboxHost` | no | `20.242.72.78` | Jumpbox public IP or hostname |
| `jumpboxUser` | no | `azureuser` | SSH username for the jumpbox |
| `storageAccountName` | yes | — | Azure Storage Account name; key is fetched automatically via the ARM service connection |
| `namespace` | no | `kube-system` | Kubernetes namespace to deploy into |
| `deploymentMode` | no | `pod` | `pod` = pin to one node · `daemonset` = all nodes |
| `captureMode` | no | `tcpdump` | `tcpdump` = auto-start capture · `shell` = idle, use `kubectl exec` |
| `releaseName` | no | `netprobe` | Helm release name — also used as the pod name in pod mode |
| `nodeName` | no | _(blank)_ | AKS node name to pin to in pod mode; blank lets the scheduler pick |
| `imageDigest` | no | _(blank)_ | `sha256:...` digest to override the value baked into `values.yaml` |
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
azureServiceConnection: sc-arm-<resourcegroup>
aksResourceGroup:      <your-resource-group>
storageAccountName:    <your-storage-account>
deploymentMode:        pod
releaseName:           debug-node-1
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpRotateSeconds:  300
```

### Capture traffic to a specific host

```
azureServiceConnection: sc-arm-<resourcegroup>
aksResourceGroup:      <your-resource-group>
storageAccountName:    <your-storage-account>
deploymentMode:        pod
releaseName:           debug-apigw
nodeName:              aks-aksnpuser-72792323-vmss00001m
tcpdumpFilterHost:     10.0.0.42
tcpdumpFilePrefix:     apigw-capture
tcpdumpRotateSeconds:  300
```

### Capture across all nodes simultaneously (DaemonSet)

```
azureServiceConnection: sc-arm-<resourcegroup>
aksResourceGroup:      <your-resource-group>
storageAccountName:    <your-storage-account>
deploymentMode:        daemonset
releaseName:           netprobe-all-nodes
tcpdumpRotateSeconds:  300
```

Files from each node are named `capture-<hostname>-<timestamp>.pcap` — they never
overwrite each other on the share.

### Interactive shell — exec in to run tools manually

```
azureServiceConnection: sc-arm-<resourcegroup>
aksResourceGroup:      <your-resource-group>
storageAccountName:    <your-storage-account>
captureMode:           shell
releaseName:           debug-shell
nodeName:              aks-aksnpuser-72792323-vmss00001m
```

Then from the jumpbox (or any host with kubectl access to the cluster):

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

### Deploy a newly published image by digest

```
releaseName:   netprobe
imageDigest:   sha256:<new-digest-from-CI>
```

---

## Post-deploy checks

Run these from the jumpbox (SSH in first: `ssh azureuser@<jumpbox-ip>`):

```bash
# Stream tcpdump output — pod mode
kubectl logs -f <releaseName> -n kube-system

# Stream from all nodes — DaemonSet mode
kubectl logs -l app.kubernetes.io/name=netprobe -n kube-system --prefix -f

# Pod status and node placement
kubectl get pod <releaseName> -n kube-system -o wide

# Confirm .pcap files are appearing on the share
az storage file list \
  --account-name <your-storage-account> \
  --share-name fileshare \
  --path dumps \
  --output table
```

---

Next: [04-destroy.md](04-destroy.md) — download captures and tear down the pod.
