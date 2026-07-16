# skore-hub-frontend Helm chart

Helm chart for the **skore-hub frontend**: a static Single Page Application (SPA) served by nginx.

This README is a quick reference for the chart itself; every option is documented inline in [`values.yaml`](values.yaml).

## What the chart deploys

| Object | Purpose |
| --- | --- |
| `Deployment` | The nginx container serving the SPA on port `80`. |
| `Service` | `ClusterIP` service exposing the UI. |
| `Ingress` | Optional HTTP(S) entry point. |

## Configuration is set at runtime

The SPA reads its settings at **runtime** from `SKH_UI_*` environment variables. Set them under `env` in your values; the image generates the `config.js` it serves to the browser at startup, so the **same image** works for every deployment. Main variables:

| Variable | Purpose |
| --- | --- |
| `SKH_UI_API_BASE_URL` | Backend API base URL (also feeds JupyterLite's `SKORE_HUB_URI`). Use an absolute URL. |
| `SKH_UI_IDP_PROFILE_SETTINGS_URL` | Link to the IdP account settings page. |
| `SKH_UI_SENTRY_DSN` | Error reporting DSN; leave empty to disable Sentry (off by default). |

See [`values.yaml`](values.yaml) for the full list of `SKH_UI_*` variables.

## Quick start

```bash
kubectl create namespace skore-hub

# Registry pull secret (same registry as the backend)
kubectl -n skore-hub create secret docker-registry scw-registry \
  --docker-server=rg.fr-par.scw.cloud \
  --docker-username='<scw-access-key>' \
  --docker-password='<scw-secret-key>'

helm upgrade --install skore-hub-ui ./skore-hub-frontend \
  -n skore-hub -f values.example.yaml
```

## Key values

| Value | Default | Description |
| --- | --- | --- |
| `image.repository` | `rg.fr-par.scw.cloud/probabl-skh/skh-ui` | Frontend image. |
| `image.tag` | `""` (falls back to `appVersion`, i.e. `0.32.0`) | Override with another version or digest if needed. |
| `imagePullSecrets` | `[]` | Registry pull secret(s). |
| `env` | `{}` | Runtime config as env vars (backend API URL, etc.). |
| `extraEnv` | `[]` | Additional raw env entries (`valueFrom`, ...). |
| `envSecret` | `""` | Load all keys of a Secret as env vars (`envFrom`). |
| `replicaCount` | `1` | Number of UI pods. |
| `service.port` | `80` | nginx listen port. |
| `ingress.enabled` | `false` | Expose via Ingress. |
| `resources` | `{}` | Pod resource requests/limits. |

See [`values.yaml`](values.yaml) for the full list and [`values.example.yaml`](values.example.yaml) for a complete example.
