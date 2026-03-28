# Potber Infrastructure

Infrastructure repository for the Potber Kubernetes setup.

## Structure

- [`hetzner/`](./hetzner): create and bootstrap the K3s cluster on Hetzner
- [`kubernetes/`](./kubernetes): Flux/GitOps setup and application manifests

## Setup order

1. Follow [`hetzner/README.md`](./hetzner/README.md)
2. Then follow [`kubernetes/README.md`](./kubernetes/README.md)
