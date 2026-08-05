# Configuration reference (`SKH__*`)

All backend settings are environment variables prefixed with `SKH__`, using `__` as the nesting delimiter (e.g. `SKH__DB__HOST` sets `db.host`).

- Put **non-sensitive** values in `skh.env` (chart values).
- Inject **secrets** (🔒) via `skh.extraEnv` → `secretKeyRef` (see [Secrets](01-installation.md#secrets)).
- List-valued settings (like CORS origins) are provided as a **JSON string**.
- A `(none)` default means there is no built-in value; set it yourself if the setting applies.

## Contents

- [General](#general)
- [Database (db)](#database-db)
- [Identity provider (idp): OIDC](#identity-provider-idp-oidc)
- [Object storage (object_storage): S3](#object-storage-object_storage-s3)
  - [GCS via S3 interoperability](#gcs-via-s3-interoperability)
- [Redis (redis)](#redis-redis)
- [SMTP (smtp)](#smtp-smtp)
- [Encryption (encryption)](#encryption-encryption)
- [Skore agent (agent)](#skore-agent-agent)
- [Cookies (cookie)](#cookies-cookie)
- [CORS (cors)](#cors-cors)
- [Observability (optional)](#observability-optional)
- [Error tracking (optional)](#error-tracking-optional)
- [Server (uvicorn)](#server-uvicorn)

## General

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__ENV` | `dev` | Environment name; set `production`. |
| `SKH__DEBUG` | `false` | Debug mode; keep `false` in production. |
| `SKH__LOG_LEVEL` | `INFO` | `DEBUG`/`INFO`/`WARNING`/`ERROR`. |
| `SKH__LOG_FORMATTER` | `default` | `json` (structured) or `default` (plain). |
| `SKH__UI_URL` | `(none)` | Public URL of the frontend. |
| `SKH__SESSION_SECRET_KEY` 🔒 | random per process | Signs cookie-based session state. The default is regenerated every time a pod starts, so sessions do not survive a restart and are not shared between replicas. Set it explicitly to a stable random value. |

## Database (`db`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__DB__HOST` | `localhost` | PostgreSQL host. |
| `SKH__DB__PORT` | `5432` | Port. |
| `SKH__DB__NAME` | `hub` | Database name. |
| `SKH__DB__USER` 🔒 | `(none)` | Username. |
| `SKH__DB__PASSWORD` 🔒 | `(none)` | Password. |
| `SKH__DB__SSL_ENABLED` | `false` | Enable TLS. |
| `SKH__DB__SSL_ROOT_CERT` | `(none)` | Path to CA cert (mount it). |
| `SKH__DB__POOL_SIZE` | `20` | Connection pool size. |
| `SKH__DB__MAX_OVERFLOW` | `10` | Extra connections beyond the pool. |

## Identity provider (`idp`): OIDC

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__IDP__IS_ENABLED` | `true` | Enable authentication. |
| `SKH__IDP__BASE_URL` | `(none)` | OIDC issuer URL (discovery base). |
| `SKH__IDP__SCOPE` | `openid offline_access` | Set `openid profile email offline_access`. |
| `SKH__IDP__CLIENT_ID` 🔒 | `(none)` | OIDC client id. |
| `SKH__IDP__CLIENT_SECRET` 🔒 | `(none)` | OIDC client secret. |
| `SKH__IDP__CACHE_EXP` | `900` | Seconds the OIDC discovery document and JWKS are cached. Lower it if your IdP rotates signing keys frequently. |

See [OIDC](01-installation.md#oidc-identity-provider) for the full setup.

## Object storage (`object_storage`): S3

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__OBJECT_STORAGE__TYPE` | `s3` | Backend driver. `s3` for any S3-compatible storage, including GCS via its S3 interoperability endpoint (see [GCS via S3 interoperability](#gcs-via-s3-interoperability)). |
| `SKH__OBJECT_STORAGE__ENDPOINT` | `http://localhost:9000` | S3 API endpoint. For GCS S3 interoperability use `https://storage.googleapis.com`. |
| `SKH__OBJECT_STORAGE__BUCKET_NAME` | `hub` | Bucket (must exist). |
| `SKH__OBJECT_STORAGE__REGION_NAME` | `(none)` | Region, if required. GCS S3 interoperability expects a region (e.g. `auto`, or a specific GCP region such as `europe-west1`). |
| `SKH__OBJECT_STORAGE__ACCESS_KEY` 🔒 | `(none)` | Access key. For GCS S3 interoperability, this is the HMAC access key of a service account. |
| `SKH__OBJECT_STORAGE__SECRET_KEY` 🔒 | `(none)` | Secret key. For GCS S3 interoperability, this is the HMAC secret of the same service account. |
| `SKH__OBJECT_STORAGE__PRESIGNED_URL_EXPIRES_IN` | `3600` | Presigned URL TTL (s). |

> Google Cloud Storage (GCS) is supported through its S3 interoperability endpoint — keep `type` as `s3` and authenticate with the HMAC keys of a GCP service account (see [GCS via S3 interoperability](#gcs-via-s3-interoperability)).

### GCS via S3 interoperability

GCS exposes an S3-compatible API at `https://storage.googleapis.com`. You keep the standard S3 configuration (`type = "s3"`) and authenticate with the HMAC keys of a GCP service account — no native GCS credentials needed. The S3 client signs requests with `s3v4`, which GCS accepts.

1. Create or pick a GCP service account, and grant it `roles/storage.objectAdmin` (or the minimum scope you need) on the bucket.
2. Create **HMAC keys** for that service account in Cloud Storage → Settings → Interoperability. You get an **Access Key** and a **Secret**.
3. Create a GCS bucket, then configure the backend:

    | Env var | Value |
    | --- | --- |
    | `SKH__OBJECT_STORAGE__TYPE` | `s3` |
    | `SKH__OBJECT_STORAGE__ENDPOINT` | `https://storage.googleapis.com` |
    | `SKH__OBJECT_STORAGE__BUCKET_NAME` | your GCS bucket name |
    | `SKH__OBJECT_STORAGE__REGION_NAME` | `auto` (or a specific GCP region) |
    | `SKH__OBJECT_STORAGE__ACCESS_KEY` 🔒 | HMAC Access Key |
    | `SKH__OBJECT_STORAGE__SECRET_KEY` 🔒 | HMAC Secret |

> The backend generates **presigned URLs**. For GCS, the S3 interoperability endpoint `https://storage.googleapis.com` must be reachable from both the backend pods and the end-user browsers / **skore Python library** that consume those URLs.

## Redis (`redis`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__REDIS__IS_ENABLED` | `false` | Enable Redis (set `true` in production). |
| `SKH__REDIS__HOST` | `localhost` | Host. |
| `SKH__REDIS__PORT` | `6379` | Port. |
| `SKH__REDIS__DB` | `0` | DB index. |
| `SKH__REDIS__USERNAME` 🔒 | `(none)` | ACL username (optional). |
| `SKH__REDIS__PASSWORD` 🔒 | `(none)` | Password (optional). |
| `SKH__REDIS__SSL` | `false` | Enable TLS. |
| `SKH__REDIS__SSL_CERT_REQS` | `required` | `required`/`optional`/`none`. |
| `SKH__REDIS__SSL_CA_CERTS` | `(none)` | CA cert path. |
| `SKH__REDIS__SSL_CERTFILE` | `(none)` | Client cert path, for mutual TLS. |
| `SKH__REDIS__SSL_KEYFILE` | `(none)` | Client key path, for mutual TLS. |
| `SKH__REDIS__MAX_CONNECTIONS` | `1000` | Pool cap. |
| `SKH__REDIS__API_KEY_VERIFICATION_CACHE_TTL_SECONDS` | `120` | API-key cache TTL; `0` disables. |

## SMTP (`smtp`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__SMTP__HOST` | `localhost` | Host. |
| `SKH__SMTP__PORT` | `1025` | Port. |
| `SKH__SMTP__USE_TLS` | `false` | STARTTLS/TLS. |
| `SKH__SMTP__USER` 🔒 | `(none)` | Username (optional). |
| `SKH__SMTP__PASSWORD` 🔒 | `(none)` | Password (optional). |
| `SKH__SMTP__SENDER` | `(none)` | From address; set your own (e.g. `no-reply@example.com`). |
| `SKH__SMTP__SENDER_NAME` | `Skore Team` | Display name shown next to the From address. |

## Encryption (`encryption`)

Fernet symmetric key used to encrypt secrets the hub persists in PostgreSQL: most importantly the per-workspace Skore agent provider credentials (Anthropic API keys, AWS/Bedrock keys, STS external ids) registered through the Hub UI. Generate with `python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"`.

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__ENCRYPTION__KEY` 🔒 | `(none)` | Fernet key. **Required** to register per-workspace agent providers. Empty disables those features. Do not rotate without re-encrypting stored secrets (see [Skore agent operations](02-operations.md#skore-agent-operations)). |

## Skore agent (`agent`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__AGENT__BACKEND` | `mock` | Global execution mode. `anthropic` enables the Skore-managed LLM path; `mock` is a key-less trace for unscoped requests only. Workspace API-key callers always use their workspace provider regardless of this value. |
| `SKH__AGENT__PROVIDER` | `anthropic` | LLM backend when `backend` is not `mock`: `anthropic` or `bedrock`. Workspaces may override via the Hub UI. |
| `SKH__AGENT__ANTHROPIC_API_KEY` 🔒 | `(none)` | Anthropic API key for the global server-side path. Empty falls back to `mock` when no workspace override applies. |
| `SKH__AGENT__MANAGED_EMAILS` | `[]` | JSON allowlist of users entitled to the Skore-managed provider. Entries are exact addresses or `*@domain` wildcards. Empty denies everyone. |
| `SKH__AGENT__MODEL_BIG` | `claude-opus-4-8` | Default Anthropic model for the big routing tier (reasoning-heavy). |
| `SKH__AGENT__MODEL_NORMAL` | `claude-sonnet-4-6` | Default Anthropic model for the normal tier (setup/tooling). |
| `SKH__AGENT__MODEL_SMALL` | `claude-haiku-4-5` | Default Anthropic model for the small tier (trivial skills). |
| `SKH__AGENT__BEDROCK_MODEL_BIG` | `(none)` | Bedrock model id for the big tier. **Required** before Bedrock routing works. |
| `SKH__AGENT__BEDROCK_MODEL_NORMAL` | `(none)` | Bedrock model id for the normal tier. |
| `SKH__AGENT__BEDROCK_MODEL_SMALL` | `(none)` | Bedrock model id for the small tier. |
| `SKH__AGENT__CACHE_TTL` | `5m` | Anthropic prompt-cache breakpoint TTL: `5m` or `1h`. |
| `SKH__AGENT__ANTHROPIC_MODELS` | `["claude-opus-4-8","claude-sonnet-4-6"]` | JSON allowlist of model ids a workspace may pin as its single model instead of tier-based "auto" routing. |
| `SKH__AGENT__BEDROCK_MODELS` | `[]` | Same for Bedrock. |
| `SKH__AGENT__AWS_REGION` | `(none)` | AWS region for Bedrock. Required when `provider` is `bedrock`. |
| `SKH__AGENT__BEDROCK_ROLE_ARN` | `(none)` | Optional IAM role to assume for cross-account Bedrock. Empty uses the ambient credential chain. |
| `SKH__AGENT__BEDROCK_EXTERNAL_ID` 🔒 | `(none)` | Optional STS `ExternalId` for `bedrock_role_arn`. |
| `SKH__AGENT__AWS_ACCESS_KEY_ID` 🔒 | `(none)` | Optional static AWS credentials. Empty uses the ambient chain (or assume-role output). |
| `SKH__AGENT__AWS_SECRET_ACCESS_KEY` 🔒 | `(none)` | Optional static AWS credentials. |
| `SKH__AGENT__ENTRY_SKILL` | `iterate-ml-experiment` | Skill id loaded at the start of a new conversation. |
| `SKH__AGENT__SESSION_TTL_SECONDS` | `3600` | Redis TTL (s) for server-side harness session state. Requires Redis when running more than one replica. |
| `SKH__AGENT__PUBLIC_MODEL_ID` | `skore-agent` | Single model id advertised to harnesses; the hub maps it to tier routing internally. |
| `SKH__AGENT__GUARDS_ENABLED` | `true` | Enable deterministic prompt-injection/extraction guards (input scan + output redaction). |

## Cookies (`cookie`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__COOKIE__HTTPONLY` | `true` | HttpOnly session cookies. |
| `SKH__COOKIE__SECURE` | `true` | Require HTTPS. |
| `SKH__COOKIE__SAMESITE` | `lax` | `lax`/`strict`/`none`. Use `none` when the frontend and API are on different hosts (requires `secure=true`). |

## CORS (`cors`)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__CORS__ALLOW_ORIGINS` | `["*"]` | JSON list of allowed origins. Set to your frontend origin. |
| `SKH__CORS__ALLOW_CREDENTIALS` | `true` | Allow cookies cross-origin. |
| `SKH__CORS__ALLOW_METHODS` | `["*"]` | JSON list. |
| `SKH__CORS__ALLOW_HEADERS` | `["*"]` | JSON list. |

## Observability (optional)

All disabled by default. See [Observability and logging](02-operations.md#observability-and-logging).

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__TEMPO__IS_ENABLED` | `false` | Enable OTLP traces. |
| `SKH__TEMPO__SERVER_ADDRESS` | `http://localhost:4317` | OTLP collector. |
| `SKH__TEMPO__INSECURE` | `true` | Send traces without TLS. Set `false` when the collector is remote. |
| `SKH__TEMPO__SERVICE_NAME` | `skore-hub` | Service name reported on traces. |
| `SKH__OTEL_METRICS__IS_ENABLED` | `false` | Enable OTLP metrics push. |
| `SKH__OTEL_METRICS__SERVER_ADDRESS` | `(none)` | OTLP metrics endpoint. |
| `SKH__OTEL_METRICS__EXPORT_INTERVAL_MILLIS` | `5000` | Export interval. |
| `SKH__PYROSCOPE__IS_ENABLED` | `false` | Enable profiling. |
| `SKH__PYROSCOPE__SERVER_ADDRESS` | `http://localhost:4040` | Pyroscope server. |
| `SKH__PYROSCOPE__APPLICATION_NAME` | `skore-hub` | Application name reported to Pyroscope. |

## Error tracking (optional)

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__SENTRY__DSN` 🔒 | `(none)` | Sentry DSN; leave empty to disable. |

## Server (`uvicorn`)

Defaults are suitable as-is; the container listens on port `8000`.

| Env var | Default | Description |
| --- | --- | --- |
| `SKH__UVICORN__HOST` | `0.0.0.0` | Bind address. |
| `SKH__UVICORN__PORT` | `8000` | Port (keep aligned with `service.port`). |

> This reference lists the settings relevant to an on-premise deployment. Other keys exist with sensible defaults; you normally do not need to change them.
