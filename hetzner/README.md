# Hetzner Cluster

K3s cluster on Hetzner Cloud managed via [hetzner-k3s](https://vitobotta.github.io/hetzner-k3s/).

## Prerequisites

- [hetzner-k3s](https://vitobotta.github.io/hetzner-k3s/Installation/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) installed
- [Helm](https://helm.sh/docs/intro/install/) installed
- [Tailscale](https://tailscale.com/download) installed and connected
- Hetzner Cloud API token
- SSH key pair at `~/.ssh/id_hetzner_cluster` / `~/.ssh/id_hetzner_cluster.pub`

## Cluster configuration

The cluster is defined in [`cluster.yaml`](./cluster.yaml).

The Hetzner API token is read from the `HETZNER_TOKEN` environment variable.

## Create the cluster

```bash
export HETZNER_TOKEN=<your-token>
gomplate -f cluster.yaml.tpl -o cluster.yaml
hetzner-k3s create --config cluster.yaml
```

## Access the cluster

Public SSH and Kubernetes API access are closed. Connect Tailscale before using
`kubectl`, SSH, or `hetzner-k3s`. The control-plane node advertises the Hetzner
private network `10.0.0.0/16` as a Tailscale subnet route.

The `kubeconfig` file uses the private API endpoint `https://10.0.0.2:6443`:

```bash
tailscale status
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

Node SSH access also uses private addresses:

```bash
ssh -i ~/.ssh/id_hetzner_cluster root@10.0.0.2
```

If Tailscale is unavailable, use the Hetzner web console for recovery. Do not
reopen public ports 22 or 6443 except for a short, explicitly monitored recovery
window.

The current cluster was migrated to Tailscale after creation. For a full cluster
rebuild, use hetzner-k3s's native Tailscale integration during provisioning; do
not attempt the initial bootstrap with `use_private_ip: true` before the private
route exists.

## Install ingress-nginx

Add the Helm repo and install ingress-nginx using the annotations file in [`ingress/`](./ingress/):

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install \
  ingress-nginx ingress-nginx/ingress-nginx \
  --set controller.ingressClassResource.default=true \
  -f ./ingress/ingress-nginx-annotations.yaml \
  --namespace ingress-nginx \
  --create-namespace
```

The annotations configure a Hetzner load balancer (`nginx-ingress-lb`) in `nbg1` with proxy protocol and HTTP→HTTPS redirect enabled for `potber.de`.

Once installed, apply the ConfigMap to enable proxy protocol support in the nginx controller:

```bash
kubectl apply -f ./ingress/ingress-nginx-configmap.yaml
```

Verify the load balancer IP is assigned:

```bash
kubectl get svc -n ingress-nginx
```

## Setup Let's Encrypt

Install cert-manager via Helm, then apply the `ClusterIssuer` for Let's Encrypt production certificates.

**1. Install cert-manager**

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install \
  --namespace cert-manager \
  --create-namespace \
  --version v1.20.5 \
  --set crds.enabled=true \
  cert-manager jetstack/cert-manager
```

**2. Apply the ClusterIssuer**

```bash
export CLUSTER_ADMIN_EMAIL=<email-address>
gomplate -f ./lets-encrypt/cert-manager.yaml.tpl -o ./lets-encrypt/cert-manager.yaml
kubectl apply -f ./lets-encrypt/cert-manager.yaml
```

## Optional: preview wildcard certificates

Preview environments under `pr-<number>.preview.potber.de` use a wildcard certificate, which requires DNS-01.

**1. Create wildcard DNS**

Create a wildcard DNS record for:

- `*.preview.potber.de`

Point it at the Kubernetes ingress load balancer.

**2. Provide a Hetzner DNS API token**

The `HETZNER_TOKEN` used to create the cluster can be reused when it has read/write access to the Hetzner Console project that contains the `potber.de` DNS zone. Alternatively, export a separate read/write token as `HETZNER_TOKEN` before creating the Kubernetes secret.

**3. Install the Hetzner DNS webhook**

cert-manager uses Hetzner's official webhook to create the DNS-01 challenge records.

```bash
helm repo add hcloud https://charts.hetzner.cloud
helm repo update hcloud

helm upgrade --install \
  --namespace cert-manager \
  --version 0.7.0 \
  cert-manager-webhook-hetzner hcloud/cert-manager-webhook-hetzner
```

**4. Create the Hetzner token secret**

```bash
kubectl create secret generic hetzner-dns-api-token-secret \
  --namespace cert-manager \
  --from-literal=token="${HETZNER_TOKEN}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

**5. Apply the preview DNS-01 issuer**

```bash
export CLUSTER_ADMIN_EMAIL=<email-address>
gomplate -f ./lets-encrypt/cert-manager-preview-hetzner-dns01.yaml.tpl -o ./lets-encrypt/cert-manager-preview-hetzner-dns01.yaml
kubectl apply -f ./lets-encrypt/cert-manager-preview-hetzner-dns01.yaml
```

The wildcard certificate itself is managed by Flux from [`../kubernetes/previews/wildcard-certificate.yaml`](../kubernetes/previews/wildcard-certificate.yaml).

## Delete the cluster

```bash
hetzner-k3s delete --config cluster.yaml
```

> **Warning:** Deleting the cluster also removes all associated Hetzner resources (nodes, load balancers, networks).

## Next step: Flux bootstrap

Once the cluster is up, ingress-nginx is installed, and cert-manager is installed, continue with the Flux handoff guide in [`../kubernetes/README.md`](../kubernetes/README.md).
