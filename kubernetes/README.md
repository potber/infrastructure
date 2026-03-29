# Flux Production Cluster

This directory is the Flux entrypoint for the production cluster.

After the Hetzner cluster is created and reachable with `kubectl`, the remaining setup is:

1. install the shared cluster components from the Hetzner guide
2. bootstrap Flux against this repository
3. restore the SOPS key so Flux can decrypt app secrets
4. verify the `potber` reconciliations

## What Flux manages here

- [`flux-system/`](./clusters/production/flux-system) contains the Flux bootstrap manifests
- [`apps.yaml`](./clusters/production/apps.yaml) reconciles `./kubernetes/apps`

The current app layout is:

- `potber-prod` namespace for production apps
- `potber-test` namespace for test apps
- `imgpot` lives in `potber-prod`

## Prerequisites

- the Hetzner cluster is already up and `kubectl get nodes` works
- [`ingress-nginx`](../hetzner/README.md) is installed
- [`cert-manager`](../hetzner/README.md) is installed
- [Flux CLI](https://fluxcd.io/flux/installation/#install-the-flux-cli) is installed
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/#kubectl) is installed
- access to the `potber/infrastructure` GitHub repository
- the existing SOPS age private key for this cluster

## 1. Use the cluster kubeconfig

The Hetzner setup writes a `kubeconfig` file to [`kubeconfig`](../hetzner/kubeconfig).

```bash
export KUBECONFIG=../hetzner/kubeconfig
kubectl get nodes
```

## 2. Bootstrap Flux

Bootstrap Flux into this cluster and point it at this repository path:

```bash
export GITHUB_TOKEN=<github-pat>

flux bootstrap github \
  --token-auth \
  --owner=potber \
  --repository=infrastructure \
  --branch=main \
  --components-extra=image-reflector-controller,image-automation-controller \
  --path=kubernetes/clusters/production
```

This creates the `flux-system` namespace, installs the controllers, and writes/updates the manifests in [`flux-system/`](./clusters/production/flux-system).

## 3. Restore the SOPS key

Application secrets in this repo are encrypted with SOPS. Flux needs the matching age private key in the cluster.

The public key for this environment is stored in [`.sops.pub.age`](./clusters/production/.sops.pub.age):

```text
age1v64geenru82d3f2fl534lsu8dwdqlvnx665gsx4yxq4e3cdkyyzq38kgd9
```

Get the matching private key from team secret storage and save it locally as:

`./clusters/production/.sops.agekey`

Then create the decryption secret:

```bash
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=./clusters/production/.sops.agekey \
  --dry-run=client -o yaml | kubectl apply -f -
```

If the private key is missing, Flux can still start, but the `potber` Kustomization will not become ready because it cannot decrypt the encrypted secrets.

## 4. Reconcile and verify

```bash
flux check

flux reconcile source git flux-system
flux reconcile kustomization potber --with-source
```

Expected checks:

```bash
kubectl -n flux-system get kustomizations
kubectl get namespaces
kubectl -n potber-prod get deploy,svc,ingress
kubectl -n potber-test get deploy,svc,ingress
```

You should see:

- `flux-system`, and `potber` with `READY=True`
- `potber-prod` and `potber-test` namespaces
- production workloads in `potber-prod`
- test workloads in `potber-test`

## Day 2 workflow

For normal changes:

1. edit manifests under [`./apps`](./apps)
2. commit and push to `main`
3. Flux applies the change automatically

## Image updates

Production should stay pinned to explicit release tags. When an app repository publishes a production release image, the follow-up workflow should update these files in this repo:

- `potber-client`, `potber-api`, `potber-auth`:
  [`./apps/potber/overlays/production/kustomization.yaml`](./apps/potber/overlays/production/kustomization.yaml)
- `imgpot`:
  [`./apps/imgpot/overlays/production/kustomization.yaml`](./apps/imgpot/overlays/production/kustomization.yaml)

The test environment is different: Flux image automation tracks the newest `main-...` image tag for `potber-client`, `potber-api`, and `potber-auth`, and commits the updated tags back to:

- [`./apps/potber/overlays/test/kustomization.yaml`](./apps/potber/overlays/test/kustomization.yaml)

Current pinned versions:

- `potber-client`: `1.28.0`
- `potber-api`: `3.3.0`
- `potber-auth`: `1.6.0`
- `imgpot`: `1.0.0`

To force an immediate sync:

```bash
flux reconcile source git flux-system
flux reconcile kustomization potber --with-source
```

## Secrets

These files are committed encrypted and decrypted by Flux in-cluster:

- [`potber-api.secret.env`](./apps/potber/overlays/production/potber-api.secret.env)
- [`potber-api.secret.env`](./apps/potber/overlays/test/potber-api.secret.env)
- [`imgpot.secret.env`](./apps/imgpot/overlays/production/imgpot.secret.env)

To edit an encrypted file locally:

```bash
export SOPS_AGE_KEY_FILE=./clusters/production/.sops.agekey
sops ./apps/potber/overlays/production/potber-api.secret.env
```

Do not use plain `kubectl apply -k` against the app tree for encrypted secrets. Let Flux do the apply.
