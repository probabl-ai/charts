# Installation

This document covers the full installation flow, in deployment order: pulling the images, configuring the external services you provide, registering the OIDC client, creating the secrets, installing the backend, deploying the frontend, and exposing everything through the Ingress.

## Contents

- [Images and registry](#images-and-registry)
- [External services](#external-services)
- [OIDC identity provider](#oidc-identity-provider)
- [Secrets](#secrets)
- [Install the backend](#install-the-backend)
- [Frontend](#frontend)
- [Ingress, TLS and DNS](#ingress-tls-and-dns)
- [Skore agent (optional)](#skore-agent-optional)

## Images and registry

The skore-hub images are published on the **Scaleway container registry**. Probabl provides you with a dedicated username/password.

- Registry host: `rg.fr-par.scw.cloud`
- Backend image: `rg.fr-par.scw.cloud/probabl-skh/skh:<tag>`
- Frontend image: `rg.fr-par.scw.cloud/probabl-skh/skh-ui:<tag>` (see [Frontend](#frontend)).

Two kinds of tags are published for each image:

- `X.Y.Z`: an immutable version tag matching the release (for example `skh:X.Y.Z`, `skh-ui:X.Y.Z`).
- `latest`: always points to the most recent release. Convenient, but it moves.

> Each chart pins a default image tag through its `appVersion` (with `imagePullPolicy: IfNotPresent`), so deployments are reproducible out of the box. The current release is `0.33.0`; see the chart `appVersion` for the exact default. If you prefer to always track the newest release, set `image.tag: latest` and `imagePullPolicy: Always`.

### Option A: Pull directly from Scaleway

Create a Kubernetes `docker-registry` pull secret in the target namespace and reference it from the chart (`imagePullSecrets`).

```bash
kubectl create namespace skore-hub

kubectl -n skore-hub create secret docker-registry scw-registry \
  --docker-server=rg.fr-par.scw.cloud \
  --docker-username='<scw-username>' \
  --docker-password='<scw-password>'
```

In your values file:

```yaml
imagePullSecrets:
  - name: scw-registry
image:
  repository: rg.fr-par.scw.cloud/probabl-skh/skh
  tag: ""                 # empty falls back to the chart appVersion; set "X.Y.Z" to override, or "latest"
  pullPolicy: IfNotPresent
```

Verify you can pull:

```bash
# from a machine with docker/podman and the credentials
docker login rg.fr-par.scw.cloud -u '<scw-username>' -p '<scw-password>'
docker pull rg.fr-par.scw.cloud/probabl-skh/skh:X.Y.Z
```

### Option B: Mirror into your internal registry (air-gapped)

If cluster nodes cannot reach the public internet, mirror the images into your internal registry and point the chart at it.

```bash
SRC=rg.fr-par.scw.cloud/probabl-skh/skh:X.Y.Z
DST=registry.internal/skore-hub/skh:X.Y.Z

# On a host that can reach both registries:
docker login rg.fr-par.scw.cloud -u '<scw-username>' -p '<scw-password>'
docker pull  "$SRC"
docker tag   "$SRC" "$DST"
docker login registry.internal
docker push  "$DST"
```

Then set `image.repository` to your internal path and create the corresponding `imagePullSecrets` (or rely on node-level registry auth).

> `skopeo copy` is a convenient alternative for mirroring without a Docker daemon: `skopeo copy docker://$SRC docker://$DST`.

### Image content (backend)

The backend image is self-contained: it bundles the API server and the Alembic migration tooling. The Helm chart runs migrations with:

```
/skh/hub/.venv/bin/alembic upgrade head
```

You do not need any separate migration image; see [Install the backend](#install-the-backend).

## External services

skore-hub connects to services **you operate**. This section lists what each one is used for and the exact `SKH__*` settings to connect to it.

> **Sensitive vs non-sensitive.** Non-sensitive settings go in `skh.env` (plain env). Secrets (passwords, keys) must come from a Kubernetes Secret via `skh.extraEnv` (`secretKeyRef`); see [Secrets](#secrets). The tables below mark secrets with 🔒.

### PostgreSQL

**Used for:** all relational/application data. The schema is created and migrated automatically by the Alembic migration Job (see [Install the backend](#install-the-backend)).

Prepare beforehand:

- A dedicated database (e.g. `skore_hub`).
- A user that **owns** that database (needs DDL rights: the migration Job creates and alters tables).
- Optionally, TLS and a CA certificate.

| Setting | Env var | Example | Notes |
| --- | --- | --- | --- |
| Host | `SKH__DB__HOST` | `postgres.internal` | |
| Port | `SKH__DB__PORT` | `5432` | |
| Database | `SKH__DB__NAME` | `skore_hub` | |
| User 🔒 | `SKH__DB__USER` | `skore_hub` | |
| Password 🔒 | `SKH__DB__PASSWORD` | | |
| TLS on/off | `SKH__DB__SSL_ENABLED` | `true` | |
| CA cert path | `SKH__DB__SSL_ROOT_CERT` | `/etc/ssl/certs/pg-ca.pem` | Mount via `volumes`/`volumeMounts`. |
| Pool size | `SKH__DB__POOL_SIZE` | `20` | Tune for `replicaCount`. |
| Pool overflow | `SKH__DB__MAX_OVERFLOW` | `10` | |

> **Connection budget.** Max connections ≈ `replicaCount × (pool_size + max_overflow)`. Make sure PostgreSQL `max_connections` accommodates it.

To mount a CA certificate for TLS, add to your values file:

```yaml
volumes:
  - name: pg-ca
    secret:
      secretName: skore-hub-pg-ca
volumeMounts:
  - name: pg-ca
    mountPath: /etc/ssl/certs/pg-ca.pem
    subPath: ca.pem
    readOnly: true
```

### Redis

**Used for:** OAuth token/state storage, API-key verification cache, and Skore agent harness session state (message history, pending tool calls) when running more than one backend replica.

| Setting | Env var | Example | Notes |
| --- | --- | --- | --- |
| Enabled | `SKH__REDIS__IS_ENABLED` | `true` | Set `true` in production. **Required** for the agent when `replicaCount > 1`. |
| Host | `SKH__REDIS__HOST` | `redis.internal` | |
| Port | `SKH__REDIS__PORT` | `6379` | |
| DB index | `SKH__REDIS__DB` | `0` | |
| Username 🔒 | `SKH__REDIS__USERNAME` | | Redis ACL user (optional). |
| Password 🔒 | `SKH__REDIS__PASSWORD` | | Optional. |
| TLS | `SKH__REDIS__SSL` | `true` | |
| TLS verify | `SKH__REDIS__SSL_CERT_REQS` | `required` | `required`/`optional`/`none`. |
| CA certs | `SKH__REDIS__SSL_CA_CERTS` | `/etc/ssl/certs/redis-ca.pem` | Mount if needed. |
| Max connections | `SKH__REDIS__MAX_CONNECTIONS` | `1000` | |
| API-key cache TTL | `SKH__REDIS__API_KEY_VERIFICATION_CACHE_TTL_SECONDS` | `120` | `0` disables caching. |

### S3-compatible object storage

**Used for:** storing uploaded artifacts and generated objects.

Prepare beforehand: a bucket and an access key / secret key with read/write on it.

| Setting | Env var | Example | Notes |
| --- | --- | --- | --- |
| Type | `SKH__OBJECT_STORAGE__TYPE` | `s3` | `s3` for standard S3-compatible storage. |
| Endpoint | `SKH__OBJECT_STORAGE__ENDPOINT` | `https://s3.internal` | Your S3 API endpoint. |
| Bucket | `SKH__OBJECT_STORAGE__BUCKET_NAME` | `skore-hub` | Must exist. |
| Region | `SKH__OBJECT_STORAGE__REGION_NAME` | `eu-west-1` | Optional, if required by your provider. |
| Access key 🔒 | `SKH__OBJECT_STORAGE__ACCESS_KEY` | | |
| Secret key 🔒 | `SKH__OBJECT_STORAGE__SECRET_KEY` | | |
| Presigned URL TTL | `SKH__OBJECT_STORAGE__PRESIGNED_URL_EXPIRES_IN` | `3600` | Seconds. |

> The backend generates **presigned URLs** for object download/upload. The `SKH__OBJECT_STORAGE__ENDPOINT` must therefore be reachable **both** from the backend pods **and** from the clients that use those URLs: end-user browsers (frontend) and the **skore Python library** in users' environments (or expose an equivalent endpoint that resolves to the same storage).

#### GCS via S3 interoperability

Google Cloud Storage works with the S3 driver above — keep `SKH__OBJECT_STORAGE__TYPE=s3` and point the endpoint at GCS's S3-compatible API:

| Setting | Env var | Example | Notes |
| --- | --- | --- | --- |
| Endpoint | `SKH__OBJECT_STORAGE__ENDPOINT` | `https://storage.googleapis.com` | GCS S3 interoperability API. |
| Bucket | `SKH__OBJECT_STORAGE__BUCKET_NAME` | `skore-hub` | GCS bucket (must exist). |
| Region | `SKH__OBJECT_STORAGE__REGION_NAME` | `auto` | Or a specific GCP region (`europe-west1`, ...). |
| Access key 🔒 | `SKH__OBJECT_STORAGE__ACCESS_KEY` | | HMAC **Access Key** of a GCP service account. |
| Secret key 🔒 | `SKH__OBJECT_STORAGE__SECRET_KEY` | | Matching HMAC **Secret**. |

Setup: create a GCP service account with `roles/storage.objectAdmin` on the bucket, then generate HMAC keys for it under **Cloud Storage → Settings → Interoperability**. The same `s3-access-key` / `s3-secret-key` Kubernetes Secret keys (see [Secrets](#secrets)) hold the HMAC Access Key / Secret. The S3 client signs with `s3v4`, which GCS accepts — no other change needed.

### SMTP

**Used for:** transactional emails (e.g. notifications). Provide a relay reachable from the cluster.

| Setting | Env var | Example | Notes |
| --- | --- | --- | --- |
| Host | `SKH__SMTP__HOST` | `smtp.internal` | |
| Port | `SKH__SMTP__PORT` | `587` | 25/465/587 depending on your relay. |
| Use TLS | `SKH__SMTP__USE_TLS` | `true` | STARTTLS/TLS. |
| User 🔒 | `SKH__SMTP__USER` | | Optional (open relays may not need it). |
| Password 🔒 | `SKH__SMTP__PASSWORD` | | Optional. |
| Sender | `SKH__SMTP__SENDER` | `no-reply@example.com` | From address. |

## OIDC identity provider

skore-hub delegates authentication to **your** OpenID Connect provider. The backend uses the standard OIDC building blocks only:

- **Discovery**: `${SKH__IDP__BASE_URL}/.well-known/openid-configuration`
- **Authorization Code flow** (browser and Python library login)
- **Token endpoint** (code exchange and refresh)
- **Userinfo endpoint** (to read the user's profile)
- **Revocation / end-session endpoints** (used for logout **if advertised** by the discovery document, optional)

### Register a client in your IdP

Create a **confidential** client (a client secret is used) with:

| Item | Value |
| --- | --- |
| Client type | Confidential (server-side, has a secret) |
| Grant types | `authorization_code`, `refresh_token` |
| Response type | `code` |
| Scopes | `openid`, `profile`, `email`, `offline_access` |
| Token endpoint auth | `client_secret_basic` or `client_secret_post` |

#### Redirect URIs

Register these **exact** callback URLs, where `<API_HOST>` is the public FQDN of the **backend** (the host on your Ingress that routes to the backend service):

```
https://<API_HOST>/identity/oauth/callback
https://<API_HOST>/identity/oauth/device/callback
```

> The backend derives the redirect URI from the incoming request host, so the public URL used by browsers must match exactly what you register (scheme, host, path). Ensure your Ingress preserves the original host and forwards `X-Forwarded-Proto: https`.

#### Claims

The `userinfo` endpoint (and/or the ID token) must expose these standard claims:

| Claim | Used for | Required |
| --- | --- | --- |
| `sub` | Stable unique user id | Yes |
| `email` | User email | Yes |
| `email_verified` | Verification flag | Recommended |
| `given_name` | First name | Recommended |
| `family_name` | Last name | Recommended |

Make sure the `profile` and `email` scopes are granted so these claims are returned; otherwise user names/emails will be empty.

### Configure skore-hub

| Setting | Env var | Example |
| --- | --- | --- |
| Enable IdP | `SKH__IDP__IS_ENABLED` | `true` |
| Issuer / base URL | `SKH__IDP__BASE_URL` | `https://sso.example.com/realms/skore` |
| Scopes | `SKH__IDP__SCOPE` | `openid profile email offline_access` |
| Client id 🔒 | `SKH__IDP__CLIENT_ID` | *(from your IdP)* |
| Client secret 🔒 | `SKH__IDP__CLIENT_SECRET` | *(from your IdP)* |

- `SKH__IDP__BASE_URL` is the **issuer** URL. The backend appends `/.well-known/openid-configuration` to discover the other endpoints, so it must be reachable from the backend pods and return the standard discovery document.

### Login / logout flow

1. The frontend sends the user to the backend `/identity/oauth/login`.
2. The backend redirects the browser to your IdP authorization endpoint.
3. After authentication, the IdP redirects back to `/identity/oauth/callback` with an authorization `code`.
4. The backend exchanges the code for tokens, reads the profile from the `userinfo` endpoint, provisions/updates the local user, and sets session cookies.
5. On **logout**, the backend revokes the tokens (if the IdP advertises a `revocation_endpoint`) and clears the cookies.

### Notes and caveats

- **User provisioning is just-in-time**: users are created/updated in skore-hub on their first successful login, from the OIDC `userinfo` claims. There is no bulk user import on this path.
- If your IdP does **not** advertise a `revocation_endpoint` or `end_session_endpoint`, logout still works (cookies are cleared); it simply won't call those endpoints.
- Use HTTPS end to end. Cookies are issued with `Secure` and `SameSite=Lax` by default (`SKH__COOKIE__SECURE`, `SKH__COOKIE__SAMESITE`).

### Quick verification

From a pod that can reach the IdP:

```bash
curl -s "${SKH__IDP__BASE_URL}/.well-known/openid-configuration" | jq \
  '{issuer, authorization_endpoint, token_endpoint, userinfo_endpoint, end_session_endpoint, revocation_endpoint}'
```

You should get a valid JSON document with at least `issuer`, `authorization_endpoint`, `token_endpoint` and `userinfo_endpoint`.

## Secrets

skore-hub reads its configuration from `SKH__*` environment variables. Sensitive values must come from Kubernetes Secrets, not from a plain values file.

### Which secrets are needed

Create a Secret (default name `skore-hub-backend-secrets`) with these keys. The keys below match the `secretKeyRef` mappings in `values.example.yaml` (`skh.extraEnv`).

| Secret key | Maps to env var | Source |
| --- | --- | --- |
| `session-secret-key` | `SKH__SESSION_SECRET_KEY` | Generate one (see below); required for stable sessions |
| `db-user` | `SKH__DB__USER` | PostgreSQL |
| `db-password` | `SKH__DB__PASSWORD` | PostgreSQL |
| `idp-client-id` | `SKH__IDP__CLIENT_ID` | OIDC |
| `idp-client-secret` | `SKH__IDP__CLIENT_SECRET` | OIDC |
| `s3-access-key` | `SKH__OBJECT_STORAGE__ACCESS_KEY` | S3 |
| `s3-secret-key` | `SKH__OBJECT_STORAGE__SECRET_KEY` | S3 |
| `redis-password` | `SKH__REDIS__PASSWORD` | Redis (if used) |
| `smtp-user` | `SKH__SMTP__USER` | SMTP (if used) |
| `smtp-password` | `SKH__SMTP__PASSWORD` | SMTP (if used) |
| `encryption-key` | `SKH__ENCRYPTION__KEY` | Skore agent (required for per-workspace providers) |
| `anthropic-api-key` | `SKH__AGENT__ANTHROPIC_API_KEY` | Skore agent (Skore-managed path, if used) |
| `bedrock-external-id` | `SKH__AGENT__BEDROCK_EXTERNAL_ID` | Skore agent Bedrock (if using assume-role) |
| `aws-access-key-id` | `SKH__AGENT__AWS_ACCESS_KEY_ID` | Skore agent Bedrock (if using static creds) |
| `aws-secret-access-key` | `SKH__AGENT__AWS_SECRET_ACCESS_KEY` | Skore agent Bedrock (if using static creds) |

> Only include the keys you actually use. If a service needs no auth (e.g. an open SMTP relay), omit its keys and remove the matching entries from `skh.extraEnv`.

Generate the session key once and keep it stable for the life of the deployment:

```bash
python -c "import secrets; print(secrets.token_urlsafe(48))"
```

Left unset, the backend generates a random one at each pod start, so sessions break on every restart and are not shared between replicas.

### Create the Secret

Create the Secret directly. The chart references it via `secretKeyRef` (`skh.extraEnv`), so nothing sensitive is stored in Helm values or history.

If you manage secrets through an external system (Vault, a cloud secret manager, SealedSecrets, an operator, ...), produce the same `skore-hub-backend-secrets` Secret with the keys above through your usual mechanism.

```bash
kubectl -n skore-hub create secret generic skore-hub-backend-secrets \
  --from-literal=db-user='skore_hub' \
  --from-literal=db-password='<db-password>' \
  --from-literal=idp-client-id='<client-id>' \
  --from-literal=idp-client-secret='<client-secret>' \
  --from-literal=s3-access-key='<s3-access-key>' \
  --from-literal=s3-secret-key='<s3-secret-key>' \
  --from-literal=redis-password='<redis-password>' \
  --from-literal=smtp-user='<smtp-user>' \
  --from-literal=smtp-password='<smtp-password>' \
  --from-literal=encryption-key='<fernet-key>' \
  --from-literal=anthropic-api-key='<sk-ant-...>'
```

Only add the Bedrock keys (`bedrock-external-id`, `aws-access-key-id`, `aws-secret-access-key`) if you use the Bedrock provider with static credentials; on EKS prefer IRSA (see [Skore agent](#skore-agent-optional)).

This is the default assumed by [Install the backend](#install-the-backend).

> **envFrom vs secretKeyRef.** By default the chart also references `skh.envSecret` via `envFrom`. If you inject every sensitive value through `skh.extraEnv` (`secretKeyRef`) as above, the two mechanisms point at the same Secret and that is fine. If you prefer to inject the whole Secret wholesale, name each Secret key exactly as the `SKH__*` env var and drop the `skh.extraEnv` mappings. To disable `envFrom` entirely, set `skh.envSecret: ""`.

### Rotation

- Rotating DB/S3/SMTP/Redis credentials or the IdP client secret: update the Secret, then restart the backend:

```bash
kubectl -n skore-hub rollout restart deploy/skore-hub-backend
```

## Install the backend

This section installs the `skore-hub-backend` Helm chart. It assumes you have:

- pulled/mirrored the image ([Images and registry](#images-and-registry)),
- prepared PostgreSQL, Redis, S3, SMTP ([External services](#external-services)),
- registered the OIDC client ([OIDC](#oidc-identity-provider)),
- created the registry pull secret and the application Secret ([Secrets](#secrets)).

Add the chart repository (once per workstation):

```bash
helm repo add probabl https://probabl-ai.github.io/charts
helm repo update
helm search repo probabl/skore-hub-backend --versions
```

### 1. Prepare your values file

Generate a starting values file from the chart defaults and adapt it:

```bash
helm show values probabl/skore-hub-backend > values.yaml
$EDITOR values.yaml
```

A ready-to-adapt example (`values.example.yaml`) is also available alongside the chart in the [repository](https://github.com/probabl-ai/charts/tree/main/charts/skore-hub-backend).

At minimum, set: `image.repository`/`image.tag`, `imagePullSecrets`, all `skh.env` connection settings, the `skh.extraEnv` secret mappings, and `ingress` (see [Ingress, TLS and DNS](#ingress-tls-and-dns)).

### 2. Validate before applying

Render the manifests locally and review them:

```bash
helm lint probabl/skore-hub-backend -f values.yaml

helm template skore-hub probabl/skore-hub-backend \
  -n skore-hub -f values.yaml | less
```

### 3. Install / upgrade

```bash
helm upgrade --install skore-hub probabl/skore-hub-backend \
  --version <chart-version> \
  -n skore-hub --create-namespace \
  -f values.yaml \
  --wait --timeout 10m
```

Pick `<chart-version>` from `helm search repo ... --versions` to pin a specific chart release; omit `--version` to install the latest.

> **Install from source (alternative).** If you prefer to work from a checkout instead of the hosted repository, clone `https://github.com/probabl-ai/charts` and point Helm at the local path, e.g. `helm upgrade --install skore-hub charts/skore-hub-backend -n skore-hub -f values.yaml`.

`--wait` blocks until the Deployment is ready. The database migration Job runs **before** the app rolls out (see below).

### Database migrations

Migrations run automatically as a Helm hook **Job** on every `install` and `upgrade`, before the new pods start:

- Command: `/skh/hub/.venv/bin/alembic upgrade head`
- Hook: `pre-install,pre-upgrade`
- The Job uses the same image and the same DB credentials as the app.

Migrations always run: the application cannot start against an un-migrated schema, so there is no toggle to skip them.

Requirements:

- The DB user must be allowed to create/alter tables (DDL) on the target database.
- Migrations are **idempotent**: re-running against an up-to-date schema is a no-op.

Inspect the migration Job:

```bash
kubectl -n skore-hub get jobs
kubectl -n skore-hub logs job/skore-hub-backend-db-migrations
```

If the Job fails, the release fails fast; fix the DB connectivity/permissions and re-run the `helm upgrade`.

### 4. Verify the rollout

```bash
kubectl -n skore-hub get pods -l app.kubernetes.io/instance=skore-hub
kubectl -n skore-hub rollout status deploy/skore-hub-backend
```

Then run the smoke tests in [Verification and smoke tests](02-operations.md#verification-and-smoke-tests).

### Common install-time settings

| Goal | Values |
| --- | --- |
| More API replicas | `replicaCount: 3` |
| Autoscaling | `autoscaling.enabled: true`, `minReplicas`, `maxReplicas` |
| CPU/memory | `resources.requests` / `resources.limits` (default example: request cpu `1` / mem `4Gi`, limit mem `4Gi`, no CPU limit) |
| Clean resource names | `fullnameOverride: skore-hub-backend` |

## Frontend

The skore-hub **frontend** is a static Single Page Application (SPA) served by **nginx**. It is delivered as:

- a container image, published on the Scaleway registry (`rg.fr-par.scw.cloud/probabl-skh/skh-ui`), and
- the **`skore-hub-frontend` Helm chart** (in this repository, under `charts/skore-hub-frontend/`).

### The frontend is configured at runtime

The SPA is configured at **runtime** through `SKH_UI_*` environment variables (most importantly the **backend API URL**), set via the chart's `env` map.

You configure the SPA by setting the `SKH_UI_*` variables below. Any variable you leave unset or empty falls back to the image's built-in default.

#### Runtime variables (`SKH_UI_*`)

| Variable | Purpose |
| --- | --- |
| `SKH_UI_API_BASE_URL` | Backend API base URL used by the SPA. Also injected into JupyterLite as `SKORE_HUB_URI` so the embedded skore library reaches the Hub (see note below). |
| `SKH_UI_IDP_PROFILE_SETTINGS_URL` | Link to the IdP account settings page, shown in the toolbar menu. |
| `SKH_UI_SENTRY_DSN` | Error reporting DSN. Leave **empty** to disable Sentry; no DSN is baked into the image, so error reporting is **off by default** and your users' frontend errors are **not** sent anywhere. |
| `SKH_UI_SENTRY_ENVIRONMENT` | Optional. Sentry environment tag (only relevant if a DSN is set). |
| `SKH_UI_SENTRY_RELEASE` | Optional. Sentry release tag. |
| `SKH_UI_BUILD_VERSION` | Optional. UI version shown in the About dialog. |
| `SKH_UI_JUPYTERLITE_URL` | Optional. Override for the JupyterLite iframe URL. |

Whatever you put under the chart's `env` map is forwarded to the container as-is.

> **JupyterLite / skore library.** The SPA embeds JupyterLite, which runs the Python `skore` library in the browser (Pyodide). It discovers the Hub through the `SKORE_HUB_URI` environment variable, which the image patches into `jupyter-lite.json` from `SKH_UI_API_BASE_URL` at startup. Because Python cannot use a relative URL, **always set `SKH_UI_API_BASE_URL` to an absolute URL**, otherwise the embedded skore library will not reach the Hub.

### Topology: frontend and API on separate hosts

Expose the frontend and the backend API on **two separate hosts**:

```
https://skore-hub.example.com       -> frontend
https://api.skore-hub.example.com   -> backend
```

Set the backend API URL on the frontend to the absolute API host:

```yaml
env:
  SKH_UI_API_BASE_URL: "https://api.skore-hub.example.com"
  SKH_UI_IDP_PROFILE_SETTINGS_URL: "https://idp.example.com/account"
  SKH_UI_SENTRY_DSN: ""
```

Because the browser origin (frontend) differs from the API origin, you **must** configure CORS and cross-site cookies on the backend:

```yaml
skh:
  env:
    SKH__UI_URL: "https://skore-hub.example.com"
    SKH__CORS__ALLOW_ORIGINS: '["https://skore-hub.example.com"]'
    SKH__CORS__ALLOW_CREDENTIALS: "true"
    # Cookies must be sent cross-site:
    SKH__COOKIE__SAMESITE: "none"
    SKH__COOKIE__SECURE: "true"
```

OIDC redirect URIs use the **API** host: `https://api.skore-hub.example.com/identity/oauth/callback`.

> `SameSite=none` requires `Secure`, so both hosts must be served over HTTPS.

### Deploy the frontend

The frontend deploys like the backend (same chart repository, same registry pull secret, same namespace):

```bash
helm show values probabl/skore-hub-frontend > frontend-values.yaml
$EDITOR frontend-values.yaml

helm upgrade --install skore-hub-ui probabl/skore-hub-frontend \
  --version <chart-version> \
  -n skore-hub -f frontend-values.yaml \
  --wait --timeout 5m
```

Set at least `image.repository`/`image.tag`, `imagePullSecrets`, the runtime `env` (`SKH_UI_API_BASE_URL`, `SKH_UI_IDP_PROFILE_SETTINGS_URL`, empty `SKH_UI_SENTRY_DSN`), and `ingress`. See the chart's [README](https://github.com/probabl-ai/charts/blob/main/charts/skore-hub-frontend/README.md) and [Ingress, TLS and DNS](#ingress-tls-and-dns).

## Ingress, TLS and DNS

This section exposes skore-hub to users over HTTPS. Adapt to your ingress controller and certificate tooling.

### DNS

Create DNS records that resolve to your ingress controller's load balancer, one per host:

- `skore-hub.example.com` (frontend)
- `api.skore-hub.example.com` (backend)

### TLS certificates

Use whichever fits your environment:

- **cert-manager** with an internal/ACME issuer (add the issuer annotation to the Ingress and let it create the `tls` secret), or
- **corporate PKI**: create a `kubernetes.io/tls` secret manually.

Manual TLS secret example:

```bash
kubectl -n skore-hub create secret tls skore-hub-api-tls \
  --cert=api.crt --key=api.key
```

### Backend Ingress (chart-managed)

The backend chart can create its own Ingress:

```yaml
ingress:
  enabled: true
  className: "nginx"          # your IngressClass
  annotations: {}             # controller-specific annotations
  hosts:
    - host: api.skore-hub.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: skore-hub-api-tls
      hosts:
        - api.skore-hub.example.com
```

The chart auto-selects the correct Ingress API version for your cluster.

### Important: preserve host and scheme

The backend builds OIDC redirect URIs from the incoming request. Your ingress / proxy must forward the original host and mark the connection as HTTPS:

- `Host` header preserved (do not rewrite to the internal Service name).
- `X-Forwarded-Proto: https` set by the TLS-terminating hop.

Most controllers do this by default. If redirect URIs come out as `http://` or with the wrong host, this is the first thing to check ([Troubleshooting](02-operations.md#troubleshooting)).

### Body size (uploads)

skore-hub uploads artifacts to S3. If you proxy uploads through the ingress, raise the max body size accordingly, e.g. for ingress-nginx:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "100m"
```

### Streaming (Skore agent)

The Skore agent exposes streaming endpoints (`/v1/chat/completions`, `/v1/messages`) that hold long-lived Server-Sent Events connections, potentially longer than a single LLM turn. The hub sets `X-Accel-Buffering: no` on these responses, but your ingress / load balancer must also cooperate:

- **Disable response buffering** for these paths (e.g. ingress-nginx `proxy-buffering: "off"`, or per-route).
- **Raise read/idle timeouts** above your longest expected LLM turn (e.g. `proxy-read-timeout: "3600"`, `proxy-send-timeout: "3600"`).
- Keep `Connection: keep-alive` and do not close idle SSE sockets early.

Example for ingress-nginx (apply to the backend Ingress, scoped to the agent paths if your controller supports path-specific annotations):

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
```

## Skore agent (optional)

The Skore agent is the hub-side LLM orchestration ("brain") exposed to harnesses (Claude Code, OpenCode, Cursor, Pi) as an OpenAI/Anthropic-compatible endpoint on `/v1/chat/completions`, `/v1/messages`, `/v1/models`. It is **off by default** (`SKH__AGENT__BACKEND=mock`) and requires configuration plus outbound LLM access to be functional.

> [!NOTE]
> **Air-gapped notice.** The agent only supports Anthropic (SaaS) and AWS Bedrock as LLM backends. A deployment with no outbound access to either is **not supported** in this version.

### Network egress

Backend pods need outbound HTTPS to the LLM provider you select:

| Provider | Egress destination | Notes |
| --- | --- | --- |
| Anthropic | `api.anthropic.com` (443) | Skore-managed path and BYO Anthropic workspaces. |
| AWS Bedrock | `bedrock-runtime.<region>.amazonaws.com` (443) + `sts.amazonaws.com` (443) | STS only needed for assume-role. |

### Required configuration

1. **Migrations** — the `agent_workspace_provider_config` table is created by the standard Alembic migration Job; no extra step.
2. **Encryption key** — set `SKH__ENCRYPTION__KEY` (Fernet) so workspaces can store their own provider credentials. See [Encryption](reference-configuration.md#encryption-encryption).
3. **Global agent settings** — at minimum `SKH__AGENT__BACKEND=anthropic` and a provider. See the full reference in [Skore agent](reference-configuration.md#skore-agent-agent).
4. **Redis** — required when `replicaCount > 1` (agent session state).

### Deployment models

| Model | What the operator provides | Per-workspace setup |
| --- | --- | --- |
| **Skore-managed** | `SKH__AGENT__ANTHROPIC_API_KEY` + `SKH__AGENT__MANAGED_EMAILS` allowlist | Activate a `skore` provider (no credentials stored) |
| **BYO Anthropic** | `SKH__ENCRYPTION__KEY` (global key may stay empty) | Register and activate an Anthropic key via the Hub UI |
| **BYO Bedrock** | AWS credentials or IAM role (see [Bedrock IAM](03-agent-setup.md)) | Register and activate AWS creds/role via the Hub UI |

Every workspace needs exactly one **active** provider in all three cases; there is no silent fallback to the global configuration.

The full onboarding workflow (provider registration, harness setup wizard, workspace API keys) is in [Agent setup](03-agent-setup.md).
