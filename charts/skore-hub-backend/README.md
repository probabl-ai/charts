# skore-hub-backend Helm chart

Helm chart for the **skore-hub backend API**. It connects to services you operate (PostgreSQL, Redis, S3-compatible storage, SMTP, and an OIDC identity provider).

This README is a quick reference for the chart itself; every option is documented inline in [`values.yaml`](values.yaml).

## What the chart deploys

| Object | Purpose |
| --- | --- |
| `Deployment` | The API server (Uvicorn/FastAPI), listening on port `8000`. |
| `Service` | `ClusterIP` service exposing the API. |
| `ConfigMap` | Optional TOML config file, mounted when `skh.config.enabled` is true. |
| `Job` (Helm hook) | Alembic database migrations, run `pre-install`/`pre-upgrade`. |
| `Ingress` | Optional HTTP(S) entry point. |
| `HorizontalPodAutoscaler` | Optional autoscaling. |
| `ServiceAccount` | Optional dedicated service account. |

## Configuration model

The application reads its configuration from three sources, in priority order (first wins; later sources only fill in keys the earlier ones omit):

1. **TOML file** mounted from a ConfigMap (`skh.config`), located via the `SKH_CONFIG_FILE` env var the chart injects automatically.
2. **`SKH__*` environment variables** (`__` is the nesting delimiter, e.g. `SKH__DB__HOST` sets `db.host`).
3. **A Kubernetes Secret** injected wholesale via `skh.envSecret` (`envFrom`).

The chart exposes four mechanisms:

- `skh.config`: a **non-sensitive** TOML file, mounted from a ConfigMap. The most readable place for host names, ports, model ids, feature toggles, ... Set `skh.config.enabled: true` and paste your TOML into `skh.config.data`. A change updates the ConfigMap and the `checksum/skh-config` pod annotation, which rolls out the `Deployment` and re-runs the migrations `Job`.
- `skh.env`: a map of **non-sensitive** settings, rendered as plain `SKH__*` env vars.
- `skh.extraEnv`: a list of env entries, typically `valueFrom.secretKeyRef` to inject **sensitive** values from a Kubernetes Secret.
- `skh.envSecret`: name of a Secret injected wholesale via `envFrom` (optional).

> **Secrets never go in `skh.config.data`** — it is stored in plaintext in a ConfigMap. Keep passwords, keys, and tokens in `skh.extraEnv` / `skh.envSecret`; the TOML only needs to omit those keys and the env vars will fill them in.

## Quick start

```bash
# 1. Registry pull secret (namespace must exist first)
kubectl create namespace skore-hub
kubectl -n skore-hub create secret docker-registry scw-registry \
  --docker-server=rg.fr-par.scw.cloud \
  --docker-username='<scw-access-key>' \
  --docker-password='<scw-secret-key>'

# 2. Application secrets (see values.example.yaml for the expected keys)
kubectl -n skore-hub create secret generic skore-hub-backend-secrets \
  --from-literal=db-user='...' \
  --from-literal=db-password='...' \
  --from-literal=idp-client-id='...' \
  --from-literal=idp-client-secret='...' \
  --from-literal=s3-access-key='...' \
  --from-literal=s3-secret-key='...' \
  --from-literal=redis-password='...' \
  --from-literal=smtp-user='...' \
  --from-literal=smtp-password='...'

# 3. Install / upgrade
helm upgrade --install skore-hub ./skore-hub-backend \
  -n skore-hub -f values.example.yaml

# 4. Smoke test
helm test skore-hub -n skore-hub
```

## Key values

| Value | Default | Description |
| --- | --- | --- |
| `image.repository` | `rg.fr-par.scw.cloud/probabl-skh/skh` | Backend image. |
| `image.tag` | `""` (falls back to `appVersion`, i.e. `0.32.0`) | Override with another version or digest if needed. |
| `imagePullSecrets` | `[]` | Registry pull secret(s). |
| `replicaCount` | `1` | Number of API pods. |
| `skh.config.enabled` | `false` | Mount a TOML config file from a ConfigMap and set `SKH_CONFIG_FILE`. |
| `skh.config.data` | `""` | Raw TOML content (non-sensitive only). |
| `skh.envSecret` | `skore-hub-backend-secrets` | Secret injected via `envFrom`. |
| `skh.env` | `{}` | Non-sensitive `SKH__*` settings. |
| `skh.extraEnv` | `[]` | Sensitive `SKH__*` via `secretKeyRef`. |
| `ingress.enabled` | `false` | Expose via Ingress. |
| `autoscaling.enabled` | `false` | Enable the HPA. |

See [`values.yaml`](values.yaml) for the full list and inline documentation, and [`values.example.yaml`](values.example.yaml) for a complete example.

## Notes

- **Logs** are written to **stdout** (set `SKH__LOG_FORMATTER=json` for structured logs). Collect them with your standard log pipeline (`kubectl logs`, Fluent Bit, Loki, etc.).
- **Health**: liveness on `/liveness`, readiness on `/readiness` (port `8000`).
- The chart does **not** create the application Secret: create it beforehand (see the Quick start above and [`values.example.yaml`](values.example.yaml) for the expected keys).
