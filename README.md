# netprobe-azure

Azure Pipelines configuration for [NetProbe](https://github.com/thev1ndu/aks-node-tcpdump) — a privileged debug pod (or DaemonSet) that deploys to an AKS node, auto-starts `tcpdump`, and writes rotating `.pcap` files directly to an Azure File Share.

This repo contains the Helm chart and both CD pipelines. No cluster shell access, no manual `kubectl run`, no tools installed at runtime.

---

## How it works

```
Developer / SRE
  │
  ├── Run Deploy Pipeline ──────────────────────────────────────────► CD Deploy  (pipelines/cd-deploy.yaml)
  │     nodeName, filterHost, rotateSeconds, interface                └─ upsert storage secret
  │                                                                      └─ helm upgrade --install
  │                                                                         └─ Pod or DaemonSet in kube-system
  │                                                                            └─ tcpdump auto-starts
  │                                                                               └─ *.pcap → Azure File Share
  │
  ├── Download .pcap from File Share ───────────────────────────────► Wireshark / tshark
  │
  └── Run Destroy Pipeline ─────────────────────────────────────────► CD Destroy (pipelines/cd-destroy.yaml)
                                                                        └─ helm uninstall → pod gone, .pcap files remain
```

### Deployment modes

| Mode | When to use |
|---|---|
| `pod` | Capture on a specific node — pin by `nodeName` |
| `daemonset` | Capture across all nodes simultaneously |

### Capture modes

| Mode | What happens |
|---|---|
| `tcpdump` | Starts automatically on container start, writes `.pcap` to the File Share |
| `shell` | Container idles (`sleep infinity`) — `kubectl exec` in and run tools manually |

---

## Repository layout

```
├── pipelines/
│   ├── cd-deploy.yaml          # CD Deploy pipeline — helm upgrade --install
│   └── cd-destroy.yaml         # CD Destroy pipeline — helm uninstall
├── charts/
│   └── netprobe/               # Helm chart (Pod + DaemonSet templates)
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
└── docs/
    ├── 01-azure-infra.md       # Storage Account, File Share, ACR, AKS pull access
    ├── 02-ado-setup.md         # Service connection, environments, variable, pipeline registration
    ├── 03-deploy.md            # Running the deploy pipeline — all parameters + examples
    ├── 04-destroy.md           # Running the destroy pipeline + downloading captures
    └── 05-troubleshooting.md   # Diagnosis and fixes for common failures
```

---

## Setup order

Do these steps once per cluster. Day-to-day use is just running the pipelines.

| Step | Document | What you do |
|---|---|---|
| 1 | [docs/01-azure-infra.md](docs/01-azure-infra.md) | Create ACR, grant AKS pull access, create Storage Account and File Share |
| 2 | [docs/02-ado-setup.md](docs/02-ado-setup.md) | Create Kubernetes service connection, ADO environments, secret variable, register pipelines |
| 3 | [docs/03-deploy.md](docs/03-deploy.md) | Run the deploy pipeline — starts the capture |
| 4 | [docs/04-destroy.md](docs/04-destroy.md) | Download captures, then run the destroy pipeline |

---

## Source repositories

| Repo | Contents |
|---|---|
| [aks-node-tcpdump](https://github.com/thev1ndu/aks-node-tcpdump) | Dockerfile, GitHub Actions CI pipeline, Azure pipeline originals |
| [netprobe-helm](https://github.com/thev1ndu/netprobe-helm) | Helm chart source (canonical) |
