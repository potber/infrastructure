# Preview Environments

This path is reconciled by Flux through [`../clusters/production/previews.yaml`](../clusters/production/previews.yaml).

The Flux `previews` Kustomization is committed in a suspended state on purpose. Resume it after the wildcard DNS record, preview DNS-01 issuer, and wildcard certificate prerequisites are in place.

It is intended for pull request previews of `potber-client` under hosts like:

- `https://pr-32.preview.potber.de`

## One-time prerequisites

- wildcard DNS record `*.preview.potber.de` pointing at the Kubernetes ingress
- `ClusterIssuer/letsencrypt-preview-cloudflare-dns01` installed in the cluster
- wildcard certificate [`wildcard-certificate.yaml`](./wildcard-certificate.yaml) able to issue `*.preview.potber.de`

## Generated manifests

The PR workflow should manage files under [`generated/`](./generated):

- create or update `generated/pr-<number>.yaml`
- ensure `generated/kustomization.yaml` includes that file in `resources:`
- remove both the file and the list entry when the PR is closed

Each generated manifest should include:

- a `ConfigMap` containing `injected-config.js`
- a `Deployment` named `potber-client-pr-<number>`
- a `Service` named `potber-client-pr-<number>`
- an `Ingress` for `pr-<number>.preview.potber.de`

Preview ingresses should use the shared wildcard TLS secret:

- `secretName: preview-potber-de-wildcard-tls`

## Workflow contract

For PR `#32`, the workflow should:

1. build and push `ghcr.io/potber/potber-client:pr-32-<sha>`
2. render a manifest from [`potber-client-preview.yaml.tpl`](./potber-client-preview.yaml.tpl)
3. write it to `kubernetes/previews/generated/pr-32.yaml`
4. update `kubernetes/previews/generated/kustomization.yaml`
5. commit and push the infra repo change
6. comment `https://pr-32.preview.potber.de` on the pull request

On PR close, it should delete `generated/pr-32.yaml`, remove the entry from `generated/kustomization.yaml`, commit, and push.

The workflow will need:

- a token with write access to `potber/infrastructure`
- `PREVIEW_API_URL`
- `PREVIEW_AUTH_URL`
- `PREVIEW_AUTH_CLIENT_ID`
- `PREVIEW_MEME_HOST_URL`

The provided template is designed to be rendered with `envsubst`.
