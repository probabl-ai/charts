# Probabl Helm charts

[![Deployment guide](https://img.shields.io/badge/docs-deployment%20guide-1f6feb)](https://probabl-ai.github.io/charts/docs/)
[![skore-hub-backend chart](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fprobabl-ai.github.io%2Fcharts%2Findex.yaml&query=%24.entries.skore-hub-backend%5B0%5D.version&label=skore-hub-backend&color=0f9d58)](charts/skore-hub-backend)
[![skore-hub-frontend chart](https://img.shields.io/badge/dynamic/yaml?url=https%3A%2F%2Fprobabl-ai.github.io%2Fcharts%2Findex.yaml&query=%24.entries.skore-hub-frontend%5B0%5D.version&label=skore-hub-frontend&color=0f9d58)](charts/skore-hub-frontend)
[![Lint charts](https://img.shields.io/github/actions/workflow/status/probabl-ai/charts/lint-test.yml?label=lint)](https://github.com/probabl-ai/charts/actions/workflows/lint-test.yml)
[![Release charts](https://img.shields.io/github/actions/workflow/status/probabl-ai/charts/release.yml?branch=main&label=release)](https://github.com/probabl-ai/charts/actions/workflows/release.yml)

Helm charts for Probabl products.

## Requirements

- Kubernetes and Helm 3.
- Access to Probabl's container registry to pull the application images. The
  charts reference private images; you need pull credentials (provided by
  Probabl) configured as an `imagePullSecret` in your namespace.
- The backing services each chart expects (databases, object storage, identity
  provider, ...), documented in the corresponding chart `README.md`.

A valid Probabl license is required to run the applications.

## Usage

```bash
helm repo add probabl https://probabl-ai.github.io/charts
helm repo update
helm search repo probabl
```

Install a chart, pinning an explicit version:

```bash
helm upgrade --install skore-hub-backend probabl/skore-hub-backend \
  --version <chart-version> \
  -n skore-hub -f my-values.yaml
```

See each chart's `README.md` and `values.yaml` for the full list of
configuration options.

## Available charts

| Chart | Description |
| --- | --- |
| [skore-hub-backend](charts/skore-hub-backend) | skore-hub backend API. |
| [skore-hub-frontend](charts/skore-hub-frontend) | skore-hub frontend (static SPA served by nginx). |

## Documentation

The full deployment and operations guide is published at
**<https://probabl-ai.github.io/charts/docs/>**:

- [Overview, architecture and prerequisites](https://probabl-ai.github.io/charts/docs/)
- [Installation](https://probabl-ai.github.io/charts/docs/01-installation/): images, external services, OIDC, secrets, backend, frontend, ingress.
- [Operations](https://probabl-ai.github.io/charts/docs/02-operations/): verification, observability/logging, troubleshooting.
- [Configuration reference](https://probabl-ai.github.io/charts/docs/reference-configuration/): every `SKH__*` setting.

The sources live under [`docs/`](docs/README.md) in this repository.

## Versioning

Each chart is versioned independently through its `Chart.yaml` `version`. The
chart `appVersion` is the default application image tag; you can override it per
release with `image.tag`.
