# Potber Infrastructure

> [!IMPORTANT]
> This repository is archived. In November 2026 potber moved to [bunny.net](https://bunny.net) and the Hetzner cluster was shut down. Nothing is deployed from here anymore; the files below document the former setup.

## Current setup

The services are configured in the Bunny dashboard and deployed by GitHub Actions in each repository. DNS for `potber.de` is hosted on Bunny DNS.

| Service                                                  | Bunny product                                                    | Deployment                                                                 |
| -------------------------------------------------------- | ---------------------------------------------------------------- | -------------------------------------------------------------------------- |
| [potber-client](https://github.com/potber/potber-client) | Storage Zone + Pull Zone (static files)                          | [Deploying](https://github.com/potber/potber-client#deploying)             |
| potber-client PR previews                                | Storage Zone + Pull Zone with Edge Script, `*.preview.potber.de` | [PR Previews](https://github.com/potber/potber-client#pr-previews)         |
| [potber-api](https://github.com/potber/potber-api)       | Magic Containers                                                 | `release_image.yml` in [potber/.github](https://github.com/potber/.github) |
| [potber-auth](https://github.com/potber/potber-auth)     | Magic Containers                                                 | `release_image.yml` in [potber/.github](https://github.com/potber/.github) |
| [imgpot](https://github.com/potber/imgpot)               | Magic Containers                                                 | `release_image.yml` in [potber/.github](https://github.com/potber/.github) |

Container images are built and pushed to GitHub Container Registry. Pushes to `main` deploy the test apps and `v*` tags deploy production, using the repository variables `BUNNY_APP_ID_TEST` and `BUNNY_APP_ID_PROD` and the secret `BUNNYNET_API_KEY`.

## Former setup

Infrastructure for the Potber Kubernetes setup on Hetzner.

### Structure

- [`hetzner/`](./hetzner): create and bootstrap the K3s cluster on Hetzner
- [`kubernetes/`](./kubernetes): Flux/GitOps setup and application manifests

### Setup order

1. Follow [`hetzner/README.md`](./hetzner/README.md)
2. Then follow [`kubernetes/README.md`](./kubernetes/README.md)
