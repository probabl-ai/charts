# Probabl Helm charts

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

The full deployment and operations guide lives under [`docs/`](docs/README.md):

- [Overview, architecture and prerequisites](docs/README.md)
- [Installation](docs/01-installation.md): images, external services, OIDC, secrets, backend, frontend, ingress.
- [Operations](docs/02-operations.md): verification, observability/logging, troubleshooting.
- [Configuration reference](docs/reference-configuration.md): every `SKH__*` setting.

## Versioning

Each chart is versioned independently through its `Chart.yaml` `version`. The
chart `appVersion` is the default application image tag; you can override it per
release with `image.tag`.
