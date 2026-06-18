# 04 — Downloading Captures and Running the Destroy Pipeline

When the capture session is complete, download the `.pcap` files first, then run the
destroy pipeline to remove the privileged pod from the cluster.

The `.pcap` files on the Azure File Share are **never deleted** by the pipeline — they
persist until you remove them manually.

---

## Prerequisites

- The deploy pipeline has been run at least once
- You know the exact `releaseName` used at deploy time

  If you are not sure, check running releases via run-command:

  ```bash
  az vmss run-command invoke \
    --resource-group <vmss-rg> \
    --name <vmss-name> \
    --instance-id 0 \
    --command-id RunShellScript \
    --scripts "helm list -n kube-system | grep netprobe"
  ```

---

## 1. Download captures

Do this before or after running destroy — the files are on the share either way.

### Download all .pcap files

```bash
az storage file download-batch \
  --account-name <your-storage-account> \
  --source "fileshare/dumps" \
  --destination ./captures \
  --pattern "*.pcap"
```

### List what is on the share without downloading

```bash
az storage file list \
  --account-name <your-storage-account> \
  --share-name fileshare \
  --path dumps \
  --query "[].name" \
  --output tsv
```

### Download a single file

```bash
az storage file download \
  --account-name <your-storage-account> \
  --share-name fileshare \
  --path dumps/<filename>.pcap \
  --dest ./<filename>.pcap
```

### Inspect without downloading

```bash
# Filter by IP address
tshark -r capture.pcap -Y "ip.addr == 10.0.0.42"

# Show HTTP requests only
tshark -r capture.pcap -Y "http.request"

# Follow a TCP stream
tshark -r capture.pcap -z follow,tcp,ascii,0
```

---

## 2. Run the Destroy pipeline

1. Open **NetProbe — CD Destroy** → **Run pipeline**
2. Fill in the parameter form

### Parameters reference

| Parameter | Required | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | yes | — | ARM Service Connection name from step 1 of ADO setup |
| `vmssName` | yes | — | Name of the jumpbox VMSS |
| `vmssResourceGroup` | yes | — | Resource group of the jumpbox VMSS |
| `vmssInstanceId` | no | `0` | VMSS instance ID to run commands on |
| `releaseName` | yes | — | The exact `releaseName` value used when the deploy pipeline was run |
| `namespace` | no | `kube-system` | Must match the namespace used at deploy time |

> `releaseName` must match exactly. A mismatch causes `helm uninstall` to target a
> different (or non-existent) release and the pipeline will fail.

---

## 3. Verify cleanup

After the pipeline succeeds, confirm via run-command:

```bash
az vmss run-command invoke \
  --resource-group <vmss-rg> \
  --name <vmss-name> \
  --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl get pods -l app.kubernetes.io/name=netprobe -n kube-system; helm list -n kube-system | grep netprobe"
```

DaemonSet pods terminate on each node independently — if pods linger briefly, wait
~60 s and re-check. Pod mode terminates within the `--timeout 60s` window.

---

## Optional — delete the share contents

The `.pcap` files persist on the share indefinitely. Delete them when no longer needed:

```bash
# Delete all files under dumps/
az storage file delete-batch \
  --account-name <your-storage-account> \
  --source "fileshare/dumps"
```

---

Next capture? Go back to [03-deploy.md](03-deploy.md).
