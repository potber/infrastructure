# Flux Production Cluster

This directory is the Flux entrypoint for the production cluster.

## What Flux reconciles here

- `infrastructure.yaml` points at `./kubernetes/infrastructure/production`
- `apps.yaml` points at `./kubernetes/potber`

Bootstrap Flux against this path:

```bash
export KUBECONFIG=/Users/kristof/Projects/potber/infra/hetzner/kubeconfig
flux bootstrap github \
  --owner=potber \
  --repository=infrastructure \
  --branch=main \
  --path=kubernetes/clusters/production
```

Flux bootstrap creates `kubernetes/clusters/production/flux-system/` in this repository and configures the cluster to sync from this directory.

## Current prerequisites

- `ingress-nginx` is still installed outside of Flux today
- `cert-manager` must already be installed before Flux can apply `lets-encrypt.yaml`

## Secret handling

The app Kustomization is configured to decrypt SOPS files with an age key stored in the `flux-system/sops-age` secret.

The public key used for encryption is committed in `.sops.pub.age`:

```text
age1v64geenru82d3f2fl534lsu8dwdqlvnx665gsx4yxq4e3cdkyyzq38kgd9
```

The private key was generated locally at `kubernetes/clusters/production/.sops.agekey` and is gitignored. Back it up somewhere safe before you rely on it for production secrets.

Create the decryption secret in the cluster before reconciling `apps.yaml`:

```bash
export KUBECONFIG=/Users/kristof/Projects/potber/infra/hetzner/kubeconfig
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=/Users/kristof/Projects/potber/infra/kubernetes/clusters/production/.sops.agekey
```

The following files are now intended to be committed in encrypted form:

- `kubernetes/potber/overlays/prod/potber-api.secret.env`
- `kubernetes/potber/overlays/prod/imgpot.secret.env`

Flux will decrypt them during reconciliation. Plain `kubectl kustomize` output remains encrypted locally, which is expected.

For local editing or inspection, point `sops` at the repo-local key:

```bash
export SOPS_AGE_KEY_FILE=/Users/kristof/Projects/potber/infra/kubernetes/clusters/production/.sops.agekey
sops /Users/kristof/Projects/potber/infra/kubernetes/potber/overlays/prod/potber-api.secret.env
```

Do not use plain `kubectl apply -k /Users/kristof/Projects/potber/infra/kubernetes/potber` once these secrets are encrypted. Flux can decrypt them; raw `kubectl` will apply encrypted values instead.
