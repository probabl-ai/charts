# Operations

This document covers what to do once the charts are installed: verifying the deployment, collecting logs and telemetry, and troubleshooting common issues.

## Contents

- [Verification and smoke tests](#verification-and-smoke-tests)
- [Observability and logging](#observability-and-logging)
- [Troubleshooting](#troubleshooting)

## Verification and smoke tests

Run these checks after installing the backend ([Install the backend](01-installation.md#install-the-backend)) and, where relevant, the frontend ([Frontend](01-installation.md#frontend)).

### 1. Pods and Job

```bash
kubectl -n skore-hub get pods -l app.kubernetes.io/instance=skore-hub
kubectl -n skore-hub rollout status deploy/skore-hub-backend

# Migration Job must have completed successfully
kubectl -n skore-hub get jobs
kubectl -n skore-hub logs job/skore-hub-backend-db-migrations
```

All backend pods should be `Running` and `Ready`.

### 2. Built-in Helm test

The chart ships a connectivity test that curls the liveness endpoint:

```bash
helm test skore-hub -n skore-hub
```

### 3. Health endpoints

Port-forward and probe the API directly (bypasses ingress):

```bash
kubectl -n skore-hub port-forward svc/skore-hub-backend 8000:8000 &

curl -fsS http://127.0.0.1:8000/liveness  && echo OK-liveness
curl -fsS http://127.0.0.1:8000/readiness && echo OK-readiness
curl -fsS http://127.0.0.1:8000/health | jq .
```

`/readiness` returns the status of each dependency. If it fails, inspect which component is `false` (DB, Redis, S3, ...) and check the corresponding settings in [External services](01-installation.md#external-services).

### 4. Dependency connectivity

From a shell inside a backend pod:

```bash
kubectl -n skore-hub exec -it deploy/skore-hub-backend -- sh

# OIDC discovery reachable?
curl -s "$SKH__IDP__BASE_URL/.well-known/openid-configuration" | head

# S3 endpoint reachable? (expect an HTTP response, not a connection error)
curl -s -o /dev/null -w '%{http_code}\n' "$SKH__OBJECT_STORAGE__ENDPOINT"
```

### 5. Through the ingress (public)

```bash
curl -fsS https://<API_HOST>/liveness && echo OK
```

Confirm TLS is valid and the host matches what you registered for OIDC.

### 6. End-to-end login

1. Open the frontend URL in a browser.
2. Trigger login → you should be redirected to your IdP.
3. Authenticate → you should be redirected back to `https://<API_HOST>/identity/oauth/callback` and land logged-in in the app.
4. Confirm your profile (name/email) is populated; this validates the OIDC `userinfo` claims and scopes ([OIDC](01-installation.md#oidc-identity-provider)).
5. Log out → session cookies are cleared.

## Observability and logging

### Logging (stdout)

skore-hub writes **all logs to `stdout`** (and `stderr`). It does not write log files and does not ship logs anywhere by itself. To collect logs, read the container output with your standard tooling.

Configure the format and verbosity:

| Setting | Env var | Values |
| --- | --- | --- |
| Log level | `SKH__LOG_LEVEL` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| Log format | `SKH__LOG_FORMATTER` | `json` (structured, recommended) or `default` (plain text) |

Read logs directly:

```bash
# Follow logs of all backend pods
kubectl -n skore-hub logs -l app.kubernetes.io/instance=skore-hub -f

# A specific pod
kubectl -n skore-hub logs <pod-name> -f

# Migration Job logs
kubectl -n skore-hub logs job/skore-hub-backend-db-migrations
```

To retain and search logs, point your existing log pipeline (Fluent Bit / Fluentd / Vector / Promtail → Loki / Elasticsearch / your SIEM) at the pods' stdout. Set `SKH__LOG_FORMATTER=json` so the collector can parse structured fields.

### Metrics & tracing (optional)

Telemetry is **disabled by default** and is entirely optional. skore-hub can push OpenTelemetry data to collectors you operate:

| Feature | Enable | Endpoint setting |
| --- | --- | --- |
| Traces (Tempo/OTLP) | `SKH__TEMPO__IS_ENABLED=true` | `SKH__TEMPO__SERVER_ADDRESS` (e.g. `http://otel-collector:4317`) |
| Metrics (OTLP push) | `SKH__OTEL_METRICS__IS_ENABLED=true` | `SKH__OTEL_METRICS__SERVER_ADDRESS` |
| Profiling (Pyroscope) | `SKH__PYROSCOPE__IS_ENABLED=true` | `SKH__PYROSCOPE__SERVER_ADDRESS` |

> **Metrics are push-only.** skore-hub exports metrics via **OTLP push** (`SKH__OTEL_METRICS__*`) to a collector you run; it does **not** expose a Prometheus `/metrics` scrape endpoint. There is therefore no `ServiceMonitor` in this chart. To collect metrics, enable the OTLP export above and point it at your OpenTelemetry collector / OTLP-compatible backend (e.g. an OTel Collector, or Prometheus with the OTLP receiver enabled).

### Health endpoints

The backend exposes three endpoints on the service port (`8000`):

| Endpoint | Purpose |
| --- | --- |
| `/liveness` | Process is up (used by the liveness probe). |
| `/readiness` | Dependencies reachable (DB, etc.), used by the readiness probe. |
| `/health` | Aggregate health with version info. |

These are wired to the Kubernetes probes by the chart (`livenessProbe`, `readinessProbe`).

## Troubleshooting

Start by reading the logs (they go to **stdout**, [Observability and logging](#observability-and-logging)):

```bash
kubectl -n skore-hub logs -l app.kubernetes.io/instance=skore-hub --tail=200
kubectl -n skore-hub describe pod <pod>
```

### Image cannot be pulled (`ImagePullBackOff` / `ErrImagePull`)

- The `imagePullSecrets` name in your values matches an existing secret in the namespace, and that secret has the correct Scaleway credentials ([Images and registry](01-installation.md#images-and-registry)).
- `image.repository` and `image.tag` are correct.
- Nodes can reach `rg.fr-par.scw.cloud` (or your mirror).

```bash
kubectl -n skore-hub get secret scw-registry -o jsonpath='{.type}'   # kubernetes.io/dockerconfigjson
```

### Migration Job fails

```bash
kubectl -n skore-hub logs job/skore-hub-backend-db-migrations
```

- **Auth/connection**: check `SKH__DB__HOST/PORT/NAME/USER/PASSWORD` and network reachability from the pod.
- **Permission denied creating tables**: the DB user needs DDL rights on the database.
- **TLS errors**: verify `SKH__DB__SSL_ENABLED` and the mounted CA cert (`SKH__DB__SSL_ROOT_CERT`).

The release fails until migrations succeed; fix and re-run `helm upgrade`.

### Pod not Ready / `readiness` failing

Query which dependency is down:

```bash
kubectl -n skore-hub port-forward svc/skore-hub-backend 8000:8000 &
curl -s http://127.0.0.1:8000/readiness | jq .
```

- DB `false` → PostgreSQL settings/network.
- Redis `false` → `SKH__REDIS__*` (and `SKH__REDIS__IS_ENABLED=true`).
- Storage `false` → `SKH__OBJECT_STORAGE__*` (endpoint reachable, bucket exists, keys valid).

### OIDC login problems

**`redirect_uri` mismatch / invalid redirect.** The redirect URI built by the backend must exactly match what is registered in the IdP:

- Register `https://<API_HOST>/identity/oauth/callback` (and `/identity/oauth/device/callback`); see [OIDC](01-installation.md#oidc-identity-provider).
- The ingress must preserve the `Host` header and set `X-Forwarded-Proto: https`, otherwise the backend may build an `http://` or wrong-host redirect URI; see [Ingress, TLS and DNS](01-installation.md#ingress-tls-and-dns).

**Discovery fails at startup.** `${SKH__IDP__BASE_URL}/.well-known/openid-configuration` must be reachable from the pod and return valid JSON. Test from inside the pod.

**Empty user name/email after login.** The `profile` and `email` scopes must be granted and the IdP `userinfo` endpoint must return `email`, `given_name`, `family_name` claims ([OIDC](01-installation.md#oidc-identity-provider)).

**Logout doesn't call the IdP.** Expected if your IdP does not advertise a `revocation_endpoint`/`end_session_endpoint`; cookies are still cleared.

### CORS / cookies

Symptoms: API calls from the SPA blocked by the browser, or the session drops right after login.

- Set `SKH__CORS__ALLOW_ORIGINS` to the exact frontend origin, and `SKH__CORS__ALLOW_CREDENTIALS=true`.
- Cross-site cookies require `SKH__COOKIE__SAMESITE=none` **and** `SKH__COOKIE__SECURE=true` (HTTPS).

### Uploads fail / 413 Request Entity Too Large

Raise the ingress body-size limit (e.g. `nginx.ingress.kubernetes.io/proxy-body-size: "100m"`), and make sure the S3 endpoint is reachable from **both** the pods and the browser ([External services](01-installation.md#external-services), [Ingress, TLS and DNS](01-installation.md#ingress-tls-and-dns)).

### Config value not taking effect

- Remember the mapping: `SKH__DB__HOST` → `db.host`, `__` is the nesting delimiter, and the prefix is always `SKH__`.
- Non-secret values live in `skh.env`; secrets are injected via `skh.extraEnv` (`secretKeyRef`). A value set in both places: the `env`/`extraEnv` list wins if duplicated; avoid defining the same variable twice.
- After changing a Secret, restart: `kubectl -n skore-hub rollout restart deploy/skore-hub-backend`.

### Inspect the effective configuration

```bash
kubectl -n skore-hub exec deploy/skore-hub-backend -- printenv | grep '^SKH__' | sort
```

(Secret values will be visible here, so run with appropriate care.)
