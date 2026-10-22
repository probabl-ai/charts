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

- [Overview, architecture and prerequisites](https://probabl-ai.github.io/charts/docs/latest/)
- [Installation](https://probabl-ai.github.io/charts/docs/latest/01-installation/): images, external services, OIDC, secrets, backend, frontend, ingress.
- [Operations](https://probabl-ai.github.io/charts/docs/latest/02-operations/): verification, observability/logging, troubleshooting.
- [Configuration reference](https://probabl-ai.github.io/charts/docs/latest/reference-configuration/): every `SKH__*` setting.

The sources live under [`docs/`](docs/README.md) in this repository.

### Documentation versions

The guide is versioned alongside chart releases and rendered with
[`mike`](https://github.com/jimporter/mike). Use the version selector in the
site header to switch between versions:

- **`latest`** (the default) is the guide for the most recent release. It is an
  alias of the newest published version, for example `/docs/0.1.14/`.
- **`dev`** is the guide built from the `main` branch, including unreleased
  changes. It is published at `/docs/dev/`.

Documentation versions follow the **`skore-hub-backend` chart version**, the
primary chart of the skore-hub release; the selector titles also show the
application version (for example `0.1.14 (app 0.45.0)`). The
`skore-hub-frontend` chart is versioned independently, but the same guide
documents both charts. A new documentation version is published when the
backend chart release for that version first appears; published snapshots are
immutable, so a frontend-only release does not create or rewrite one (its
documentation changes are picked up by the next backend release). Each
snapshot is built with a version-specific canonical URL, so search engines
link to the documentation version matching the release. To find the guide for
an installed release:

```bash
helm list -n skore-hub
# NAME       NAMESPACE  REVISION  UPDATED  STATUS    CHART                     APP VERSION
# skore-hub  skore-hub  3         ...      deployed  skore-hub-backend-0.1.14  0.45.0
```

New versions are published automatically by the
[release workflow](.github/workflows/release.yml) whenever chart-releaser
publishes a chart, and the `dev` version is refreshed by the
[docs workflow](.github/workflows/docs.yml) on every documentation or chart
change on `main`. The 10 most recent release versions are retained; older
versions are pruned automatically. The `.github/scripts/prune-docs-versions.py`
script implements that retention policy.

## Versioning

Each chart is versioned independently through its `Chart.yaml` `version`. The
chart `appVersion` is the default application image tag; you can override it per
release with `image.tag`. Documentation is versioned per
`skore-hub-backend` chart release, as described above.
