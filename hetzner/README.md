# Hetzner Cluster

K3s cluster on Hetzner Cloud managed via [hetzner-k3s](https://vitobotta.github.io/hetzner-k3s/).

## Prerequisites

- [hetzner-k3s](https://vitobotta.github.io/hetzner-k3s/Installation/) installed
- [kubectl](https://kubernetes.io/docs/tasks/tools/#kubectl) installed
- [Helm](https://helm.sh/docs/intro/install/) installed
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

The `kubeconfig` file is written to this directory after creation. Export it to use `kubectl`:

```bash
export KUBECONFIG=./kubeconfig
kubectl get nodes
```

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

**2. Create the Cloudflare token secret**

The token needs permission to edit DNS records for the `potber.de` zone.

```bash
kubectl create secret generic cloudflare-preview-api-token-secret \
  --namespace cert-manager \
  --from-literal=api-token=<cloudflare-api-token> \
  --dry-run=client -o yaml | kubectl apply -f -
```

**3. Apply the preview DNS-01 issuer**

```bash
export CLUSTER_ADMIN_EMAIL=<email-address>
gomplate -f ./lets-encrypt/cert-manager-preview-cloudflare-dns01.yaml.tpl -o ./lets-encrypt/cert-manager-preview-cloudflare-dns01.yaml
kubectl apply -f ./lets-encrypt/cert-manager-preview-cloudflare-dns01.yaml
```

The wildcard certificate itself is managed by Flux from [`../kubernetes/previews/wildcard-certificate.yaml`](../kubernetes/previews/wildcard-certificate.yaml).

## Delete the cluster

```bash
hetzner-k3s delete --config cluster.yaml
```

> **Warning:** Deleting the cluster also removes all associated Hetzner resources (nodes, load balancers, networks).

## Next step: Flux bootstrap

Once the cluster is up, ingress-nginx is installed, and cert-manager is installed, continue with the Flux handoff guide in [`../kubernetes/README.md`](../kubernetes/README.md).
