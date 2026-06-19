# 04 — Downloading Captures and Running the Destroy Pipeline

When the capture session is complete, download the `.pcap` files first, then run the
destroy pipeline to remove the privileged pod from the cluster.

The `.pcap` files on the Azure File Share are **never deleted** by the pipeline — they
persist until you remove them manually.

---

## Prerequisites

- The deploy pipeline has been run at least once
- You know the exact `releaseName` used at deploy time

  If you are not sure, check running releases:

  ```bash
  helm list -n kube-system | grep netprobe
  ```

---

## 1. Download captures

Do this before or after running destroy — the files are on the share either way.

### Download all .pcap files

```bash
az storage file download-batch \
  --account-name sa18436 \
  --source "fileshare/dumps" \
  --destination ./captures \
  --pattern "*.pcap"
```

### List what is on the share without downloading

```bash
az storage file list \
  --account-name sa18436 \
  --share-name fileshare \
  --path dumps \
  --query "[].name" \
  --output tsv
```

### Download a single file

```bash
az storage file download \
  --account-name sa18436 \
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
| `kubernetesServiceConnection` | no | `rnd-aks-thevindu` | Kubernetes Service Connection name |
| `namespace` | no | `kube-system` | Must match the namespace used at deploy time |

> `releaseName` must match exactly. A mismatch causes `helm uninstall` to target a
> different (or non-existent) release and the pipeline will fail.

---

## 3. Verify cleanup

```bash
# Should return nothing
kubectl get pods -l app.kubernetes.io/name=netprobe -n kube-system

# Should show no releases
helm list -n kube-system | grep netprobe
```

DaemonSet pods terminate on each node independently — if pods linger briefly, wait
~60 s and re-check. Pod mode terminates within the `--timeout 60s` window.

---

## Optional — delete the share contents

The `.pcap` files persist on the share indefinitely. Delete them when no longer needed:

```bash
az storage file delete-batch \
  --account-name sa18436 \
  --source "fileshare/dumps"
```

---

Next capture? Go back to [03-deploy.md](03-deploy.md).
