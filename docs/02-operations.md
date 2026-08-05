# Operations

This document covers what to do once the charts are installed: verifying the deployment, collecting logs and telemetry, and troubleshooting common issues.

## Contents

- [Verification and smoke tests](#verification-and-smoke-tests)
- [Observability and logging](#observability-and-logging)
- [Troubleshooting](#troubleshooting)
- [Skore agent operations](#skore-agent-operations)

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

| Setting | Env var | TOML key | Values |
| --- | --- | --- | --- |
| Log level | `SKH__LOG_LEVEL` | `log_level` | `DEBUG`, `INFO`, `WARNING`, `ERROR` |
| Log format | `SKH__LOG_FORMATTER` | `log_formatter` | `json` (structured, recommended) or `default` (plain text) |

Set these as env vars (`skh.env`) or in `skh.config.data` ([ConfigMap](01-installation.md#configuration-via-configmap-toml)). TOML takes priority.

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

These map to the `[tempo]`, `[otel_metrics]` and `[pyroscope]` TOML tables (`is_enabled`, `server_address`, ...) when you use `skh.config.data`. TOML takes priority over the `SKH__*` env vars.

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
- **Priority order (first wins):** a mounted TOML file (`skh.config.data`, located via `SKH_CONFIG_FILE`) → `SKH__*` env vars (`skh.env`, `skh.extraEnv`, `skh.envSecret`) → built-in defaults. A key set in the TOML overrides an env var with the same meaning, so check both places. See [Configuration via ConfigMap (TOML)](01-installation.md#configuration-via-configmap-toml).
- Non-secret values live in `skh.config.data` or `skh.env`; secrets are injected via `skh.extraEnv` (`secretKeyRef`) / `skh.envSecret`. Avoid defining the same key in two sources.
- After changing a Secret, restart: `kubectl -n skore-hub rollout restart deploy/skore-hub-backend`. After changing `skh.config.data`, a `helm upgrade` rolls the pods automatically (via the `checksum/skh-config` annotation).

### Inspect the effective configuration

```bash
# Env vars actually set on the pod (does NOT show the TOML file):
kubectl -n skore-hub exec deploy/skore-hub-backend -- printenv | grep '^SKH__' | sort

# The mounted TOML file, if skh.config.enabled is true:
kubectl -n skore-hub exec deploy/skore-hub-backend -- cat "${SKH_CONFIG_FILE:-/etc/skh/config.toml}"
```

(Secret values will be visible here, so run with appropriate care.) Remember a key set in the TOML takes priority over an env var with the same meaning; check both to understand the effective value.

## Skore agent operations

Operational notes specific to the Skore agent ([setup](03-agent-setup.md), [config reference](reference-configuration.md#skore-agent-agent)).

### Verify the agent is reachable

```bash
# From inside a backend pod (bypasses ingress):
kubectl -n skore-hub exec deploy/skore-hub-backend -- \
  curl -s http://127.0.0.1:8000/v1/models | jq .
```

The response must list `skore-agent` (the `SKH__AGENT__PUBLIC_MODEL_ID`). If the list is empty or the endpoint 404s, the agent router is not mounted. Check the image version and that migrations ran.

### Agent metrics (token usage)

The agent exports token-usage metrics through the same OTLP push path as the rest of the hub. Enable it with:

| Setting | Env var |
| --- | --- |
| Enable OTLP metrics | `SKH__OTEL_METRICS__IS_ENABLED=true` |
| OTLP endpoint | `SKH__OTEL_METRICS__SERVER_ADDRESS` |

A ready-made Grafana dashboard for agent token usage ships with the hub source at `docker/grafana-dashboards/agent-token-usage.json`. Import it into your Grafana if you surface hub metrics there.

### Troubleshooting

**`HTTP 400 no_active_provider`.** The workspace has no *active* LLM provider. Every workspace needs one provider registered **and activated** in the Hub UI, including for Skore-managed inference, where the provider is of type `skore` ([Agent setup](03-agent-setup.md)). There is no silent fallback to the global configuration.

**`HTTP 400 no_workspace`.** The request could not be scoped to a workspace: the caller used neither a workspace-scoped API key nor a valid `X-Skore-Workspace` header (the workspace slug, and the user must be a member of it). Unscoped requests only succeed when the deployment runs with `SKH__AGENT__BACKEND=mock`.

**`HTTP 503` after rotating `SKH__ENCRYPTION__KEY`.** Per-workspace provider credentials are encrypted at rest with the Fernet key. Rotating the key without re-encrypting the stored secrets makes them unreadable and the agent returns 503. To rotate: decrypt existing provider credentials with the old key, re-encrypt with the new key, then roll the pods. There is no automatic re-encryption in this version.

**Agent calls hang / SSE drops.** Long-lived streaming responses on `/v1/chat/completions` and `/v1/messages` need ingress timeouts longer than the longest LLM turn and response buffering disabled ([Streaming](01-installation.md#streaming-skore-agent)). If calls cut off after ~60s, check `proxy-read-timeout`/`proxy-send-timeout` on your ingress.

**Sessions lost across replicas.** With `replicaCount > 1`, agent session state must live in Redis. Confirm `SKH__REDIS__IS_ENABLED=true` and that all replicas reach the same Redis instance. Without Redis, a conversation routed to a different pod has no history and starts over.

**Bedrock `AccessDenied` / `ExpiredToken`.** Either the static AWS credentials are wrong/expired, or the IAM role (IRSA / assume-role) lacks `bedrock:InvokeModel` on the target model. A policy scoped to the inference profile alone is a common cause: a cross-region profile also needs the underlying foundation model allowed in every region it can reach ([AWS-side prerequisites](03-agent-setup.md#aws-side-prerequisites)). For cross-account access via `SKH__AGENT__BEDROCK_ROLE_ARN`, the assumed role's trust policy must allow the caller with the configured `SKH__AGENT__BEDROCK_EXTERNAL_ID`.

**Bedrock `ResourceNotFoundException: Model use case details have not been submitted`.** An account-level gate on Anthropic models, not an IAM problem. Submit the *Anthropic use case details* form in the Bedrock console and allow up to 15 minutes for it to propagate ([AWS-side prerequisites](03-agent-setup.md#aws-side-prerequisites)).

**Bedrock `ValidationException` on prompt caching.** The workspace pinned a non-Anthropic Bedrock model. Only Anthropic models on Bedrock are supported in this version ([Deployment models](03-agent-setup.md#minimal-global-config-by-model)).
