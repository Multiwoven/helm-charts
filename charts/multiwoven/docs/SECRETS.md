# Secrets Management: Current State and Migration Plan

This document describes how the `multiwoven` chart currently handles secrets,
inventories the sensitive values that are **not** yet handled that way, and
proposes a design for closing the gap using the pattern already established
in the chart.

Status: proposal. No templates have been changed yet — this is the plan for
the `convert-sensitive-values-to-secrets` work.

## 1. What the chart already does

### 1.1 AWS Secrets Manager → CSI → synced `Secret` (the real pattern)

Four database credential pairs are handled correctly today via the
[Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
with the AWS provider:

| Group | SecretProviderClass template | Toggle | AWS secret name (values) | Synced k8s Secret name |
|---|---|---|---|---|
| Multiwoven app DB | `multiwoven-secret-provider-class-mw.yaml` | `secretsStore.enabled` | `secretsStore.MWCredsSecretName` | `secretsStore.mwSecretAlias` |
| Temp store DB | `multiwoven-secret-provider-class-temp-store.yaml` | `secretsStore.tempStoreSecretEnabled` | `secretsStore.TempStoreCredsSecretName` | `secretsStore.tempStoreSecretAlias` |
| Temporal DB | `multiwoven-secret-provider-class-temporal.yaml` | `secretsStore.temporalSecretEnabled` | `secretsStore.TemporalCredsSecretName` | `secretsStore.temporalSecretAlias` |
| Temporal visibility DB | `multiwoven-secret-provider-class-temporal-visibility.yaml` | `secretsStore.temporalSecretEnabled` | `secretsStore.TemporalVisibilityCredsSecretName` | `secretsStore.temporalVisibilitySecretAlias` |

The shape, using the mw group as the canonical example
([multiwoven-secret-provider-class-mw.yaml](../templates/multiwoven-secret-provider-class-mw.yaml)):

```yaml
{{ if .Values.secretsStore.enabled }}
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: {{ include "chart.fullname" . }}-secret-provider-class-mw
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: {{ required "MWCredsSecretName is required" .Values.secretsStore.MWCredsSecretName }}
        objectType: secretsmanager
        jmesPath:
          - path: u
            objectAlias: MW_DB_USERNAME
          - path: p
            objectAlias: MW_DB_PASSWORD
  secretObjects:
  - secretName: {{ .Values.secretsStore.mwSecretAlias }}
    type: Opaque
    data:
      - objectName: MW_DB_PASSWORD
        key: MW_DB_PASSWORD
      - objectName: MW_DB_USERNAME
        key: MW_DB_USERNAME
{{ end }}
```

The AWS secret is a JSON blob with short keys `u`/`p`. The CSI driver pulls it,
extracts `u`/`p` via `jmesPath`, and `secretObjects` tells the driver to
mirror those values into a real, namespaced `Opaque` Secret (this "sync"
behavior is what lets a Secret-backed value be consumed via a normal
`secretKeyRef`, not just via the CSI volume mount).

Consumption in [multiwoven-server-deployment.yaml](../templates/multiwoven-server-deployment.yaml):

- **Volume mount** — the CSI volume must be mounted for the sync to happen at all:
  ```yaml
  volumes:
  {{ if .Values.secretsStore.enabled }}
  - name: multiwoven-secrets-store
    csi:
      driver: secrets-store.csi.k8s.io
      readOnly: true
      volumeAttributes:
        secretProviderClass: {{ include "chart.fullname" . }}-secret-provider-class-mw
  {{ end }}
  ```
  mounted at `/run/secrets/mw-secrets` in the container.
- **Env vars** — actual consumption is via `secretKeyRef` against the synced Secret, not the mounted files:
  ```yaml
  {{ if .Values.secretsStore.enabled }}
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secretsStore.mwSecretAlias }}
        key: MW_DB_PASSWORD
  {{ end }}
  ```
- **Plaintext fallback** — [multiwoven-config.yaml](../templates/multiwoven-config.yaml) only puts `DB_PASSWORD`/`DB_USERNAME` in the ConfigMap `{{ if not .Values.secretsStore.enabled }}`, so community/local installs that don't have AWS Secrets Manager still work out of the box.

### 1.2 Pre-existing `Secret` referenced by name only

`multiwovenConfig.registrySecretName` (default `mwregistrysecret`) is used as
an `imagePullSecrets` reference in every Deployment
(`multiwoven-server-deployment.yaml`, `multiwoven-ui-deployment.yaml`,
`box-deployment.yaml`, `lightning-deployment.yaml`,
`multiwoven-worker-deployment.yaml`, `multiwoven-solid-worker-deployment.yaml`,
`temporal-deployment.yaml`, `temporal-ui-deployment.yaml`). This chart never
creates that Secret — it's expected to pre-exist in the namespace (e.g.
created by the operator via `kubectl create secret docker-registry`). This is
a valid, simpler pattern worth keeping in mind for anything that's created
once, out-of-band, and just referenced by name.

### 1.3 Everything else: plaintext `ConfigMap` / `values.yaml`

Everything not in 1.1 flows straight from `values.yaml` into a `ConfigMap`
that's wired to each Deployment via `envFrom.configMapRef`:

| Component | ConfigMap template | values.yaml section | Consuming Deployment(s) |
|---|---|---|---|
| Core app | `multiwoven-config.yaml` | `multiwovenConfig`, `sandboxConfig` (partially) | server, ui, worker, solid-worker |
| Box orchestrator | `box-config.yaml` | `boxConfig` | box |
| Lightning (model gateway) | `lightning-config.yaml` | `lightningConfig` | lightning |

`box-config.yaml` even says so directly today:

> `# NOTE: Sensitive values (API keys, DB credentials) are stored here temporarily.`
> `#       A secret management solution (e.g. secrets-store CSI) should be wired in later.`

That's the gap this document proposes closing, for all three ConfigMaps.

## 2. Inventory: sensitive values still in plaintext

"Sensitive" = credential, API key/token, signing/encryption secret, or a
password — i.e., something that grants access or proves identity, as opposed
to a hostname, port, feature flag, or other non-secret config.

### 2.1 `multiwovenConfig` (→ `multiwoven-config.yaml`)

| Key | Env var |
|---|---|
| `awsAccessKeyId` | `AWS_ACCESS_KEY_ID` |
| `awsSecretAccessKey` | `AWS_SECRET_ACCESS_KEY` |
| `appsignalPushApiKey` | `APPSIGNAL_PUSH_API_KEY` |
| `boxApiKey` | `BOX_API_KEY` |
| `codeExecSigningSecret` | `CODE_EXEC_SIGNING_SECRET` |
| `dbUsername` †  | `DB_USERNAME` |
| `dbPassword` †  | `DB_PASSWORD` |
| `hostedVectorDbUsername` | `HOSTED_VECTOR_DB_USERNAME` |
| `hostedVectorDbPassword` | `HOSTED_VECTOR_DB_PASSWORD` |
| `hubspotApiKey` | `HUBSPOT_API_KEY` |
| `jwtSecret` | `JWT_SECRET` |
| `maxmindLicenseKey` | `MAXMIND_LICENSE_KEY` |
| `neonApiKey` | `NEON_API_KEY` |
| `openrouterApiKey` | `OPENROUTER_API_KEY` |
| `p2wLlmApiKey` | `P2W_LLM_API_KEY` |
| `prometheusMetricsUsername` | `PROMETHEUS_METRICS_USERNAME` |
| `prometheusMetricsPassword` | `PROMETHEUS_METRICS_PASSWORD` |
| `promptToWorkflowApiKey` | `PROMPT_TO_WORKFLOW_API_KEY` |
| `secretKeyBase` | `SECRET_KEY_BASE` |
| `smtpUsername` | `SMTP_USERNAME` |
| `smtpPassword` | `SMTP_PASSWORD` |
| `storageAccessKey` | `STORAGE_ACCESS_KEY` |
| `textractAccessKeyId` | `TEXTRACT_ACCESS_KEY_ID` |
| `textractSecretAccessKey` | `TEXTRACT_SECRET_ACCESS_KEY` |
| `temporalPostgresUser` ‡ | `TEMPORAL_POSTGRES_USER` |
| `temporalPostgresPassword` ‡ | `TEMPORAL_POSTGRES_PASSWORD` |

**† `dbUsername`/`dbPassword`** are already fully covered — no new work
needed for these two specifically. They're gated `{{ if not
.Values.secretsStore.enabled }}` in
[multiwoven-config.yaml:56-59](../templates/multiwoven-config.yaml), and
every consuming Deployment (server/worker/solid-worker) sources them via
`secretKeyRef` against the existing `mw` group
(`secretsStore.mwSecretAlias`) when `secretsStore.enabled` is `true`. They're
listed here anyway because the table is meant to show everything that's
plaintext **by default** (`secretsStore.enabled` defaults to `false`) — same
caveat applies to every group flag proposed in §3, so it'd be inconsistent
to hide these two just because their flag happens to already exist.

**‡ `temporalPostgresUser`/`temporalPostgresPassword` are a real gap, not
just an inventory omission.** These aren't just "not yet secret-ified" like
the rest of the table — the existing gating on `temporalPostgresPassword`
is actively wrong:

```yaml
{{ if not .Values.secretsStore.enabled }}
TEMPORAL_POSTGRES_PASSWORD: {{ .Values.multiwovenConfig.temporalPostgresPassword | quote }}
{{ end }}
TEMPORAL_POSTGRES_USER: {{ .Values.multiwovenConfig.temporalPostgresUser | quote }}
```

Two problems:
1. It's gated on `secretsStore.enabled` (the **mw** DB flag), not
   `secretsStore.temporalSecretEnabled` (the flag that actually governs the
   Temporal secret group these values belong to). An operator who enables
   `temporalSecretEnabled` without also enabling the unrelated `enabled`
   flag gets no protection here at all — the value stays plaintext despite
   them believing they'd secured it.
2. `TEMPORAL_POSTGRES_USER` isn't gated by anything, ever.
3. There is no `secretKeyRef` fallback for either key anywhere in this
   chart (confirmed via `grep -rn "TEMPORAL_POSTGRES" templates/`) — so
   even in the one case where the password *is* correctly omitted
   (`secretsStore.enabled: true`), nothing replaces it. It just goes
   missing from the env of every pod that pulls this ConfigMap
   (server/worker/solid-worker/ui, all via `envFrom.configMapRef`).

This should be fixed regardless of whether the broader `app`-group
migration in §3 happens — it's a pre-existing correctness bug, not a nice-
to-have. The fix doesn't belong in the new `app` group, though — see the
rewritten §2.5 below. These are Temporal's own DB credentials, and a
`temporal` secret group already exists; the fix is to reuse it, and to stop
also duplicating these values inside `multipleDbHosts` in the first place.

**Deliberately excluded:** `viteAppsignalPushApiKey` (`VITE_APPSIGNAL_PUSH_API_KEY`).
It's consumed by [multiwoven-ui-deployment.yaml](../templates/multiwoven-ui-deployment.yaml),
whose entire job is to serve the built frontend bundle — anything with a
`VITE_` prefix is Vite convention for "gets inlined into client-side JS and
served to every visitor's browser." Moving it into a Kubernetes Secret
wouldn't reduce its exposure, since the value ends up in a publicly
fetchable `.js` file either way; it would just add CSI/IAM machinery around
a value that's public by design. Treat it the same as the other `vite*`
keys (`viteApiHost`, `viteBrandName`, etc.) — config, not a secret to guard.
If this key is ever rotated because it *leaked* in a way that mattered
(e.g. the underlying Appsignal key also grants write/delete access
server-side), that's a signal it shouldn't be a `VITE_` var at all, not a
signal to secret-ify it in place.

### 2.2 `sandboxConfig` (→ `multiwoven-config.yaml`)

| Key | Env var |
|---|---|
| `agenticCodingBuildToken` | `AGENTIC_CODING_BUILD_TOKEN` |
| `codingAgentModelApiKey` | `CODING_AGENT_MODEL_API_KEY` |
| `modalTokenId` | `MODAL_TOKEN_ID` |
| `modalTokenSecret` | `MODAL_TOKEN_SECRET` |
| `dockerHubRegistryUsername` | `DOCKER_HUB_REGISTRY_USERNAME` |
| `dockerHubRegistryPassword` | `DOCKER_HUB_REGISTRY_PASSWORD` |

### 2.3 `boxConfig` (→ `box-config.yaml`)

| Key | Env var |
|---|---|
| `boxApiKey` | `BOX_API_KEY` |
| `boxEncryptionKey` | `BOX_ENCRYPTION_KEY` |
| `dbUsername` | `DB_USERNAME` |
| `dbPassword` | `DB_PASSWORD` |

### 2.4 `lightningConfig` (→ `lightning-config.yaml`)

Every model backend has an API key:

`babelApiKey`, `polyApiKey`, `chatApiKey`, `embeddingApiKey`, `judyApiKey`,
`multimodalChatApiKey`, `pathfinderApiKey`, `seemoreApiKey`,
`sentinelApiKey`, `structuredExtractionApiKey`, `xpertApiKey`

→ `BABEL_API_KEY`, `POLY_API_KEY`, `CHAT_API_KEY`, `EMBEDDING_API_KEY`,
`JUDY_API_KEY`, `MULTIMODAL_CHAT_API_KEY`, `PATHFINDER_API_KEY`,
`SEEMORE_API_KEY`, `SENTINEL_API_KEY`, `STRUCTURED_EXTRACTION_API_KEY`,
`XPERT_API_KEY`.

### 2.5 `multipleDbHosts` — streamline, don't treat as a secrets group

`multipleDbHosts` exists for one narrow edge case: an operator whose managed
Postgres (e.g. RDS) only allows one database per instance, so `multiwoven`,
`temporal`, and `temporal-visibility` each need to point at a *different
host*. Its job should be exactly that — host/database-name overrides — and
nothing about how credentials are sourced should depend on it.

Today it's not quite that clean. `multiwovenDBHost`/`multiwovenDBName` are
pure topology, correctly — the mw credentials always come from the `mw`
secret group regardless of `multipleDbHosts.enabled`, no duplication. But
`temporalDbUsername`/`temporalDbPassword` and
`temporalVisibilityDbUsername`/`temporalVisibilityDbPassword` currently
*live inside* `multipleDbHosts` as the plaintext-fallback values for
Temporal's DB creds, and are only consulted inside the
`{{ if .Values.multipleDbHosts.enabled }}` branch of
[temporal-deployment.yaml](../templates/temporal-deployment.yaml). That
conflates two unrelated concerns: "which host does Temporal's DB live on"
and "what is the fallback value of Temporal's DB password." Now that DB
credentials are formally in scope for this migration rather than an
incidental side effect of one topology flag, that coupling should go away
— `multipleDbHosts` shouldn't be *the home* for any credential, even a
fallback one.

**Streamlined design:**

1. Move the credential fields out of `multipleDbHosts` and into
   `multiwovenConfig`, alongside the other DB creds it already holds
   (`dbUsername`/`dbPassword` for the `mw` group):
   - `temporalPostgresUser`/`temporalPostgresPassword` — these already
     exist in `multiwovenConfig` (see the ‡ bug above), so this is a
     rename-in-place of intent more than a new field: they become the one
     canonical fallback for Temporal's DB credentials, used **regardless of
     `multipleDbHosts.enabled`**, instead of being dead weight that nothing
     currently wires up.
   - `temporalVisibilityPostgresUser`/`temporalVisibilityPostgresPassword`
     — new fields, the equivalent for the visibility store.
2. `multipleDbHosts` shrinks to pure topology:
   ```yaml
   multipleDbHosts:
     enabled: false
     multiwovenDBHost: ""
     multiwovenDBName: ""
     temporalDbName: ""
     temporalDbHost: ""
     temporalVisibilityDbName: ""
     temporalVisibilityDbHost: ""
   ```
   (`temporalDbUsername`, `temporalDbPassword`,
   `temporalVisibilityDbUsername`, `temporalVisibilityDbPassword` removed.)
3. In `temporal-deployment.yaml`, the `multipleDbHosts.enabled` branch's
   `TEMPORAL_DEFAULT_USER`/`TEMPORAL_DEFAULT_PASSWORD` and
   `TEMPORAL_VISIBILITY_USER`/`TEMPORAL_VISIBILITY_PASSWORD` now read their
   plaintext fallback from `multiwovenConfig.temporalPostgresUser` /
   `temporalPostgresPassword` / `temporalVisibilityPostgresUser` /
   `temporalVisibilityPostgresPassword` instead of the `multipleDbHosts`
   fields being removed. The `secretKeyRef` half of each branch is
   **unchanged** — it already points at the existing `temporal` /
   `temporal-visibility` groups (`temporalSecretAlias`/`TP_DB_*`,
   `temporalVisibilitySecretAlias`/`TPV_DB_*`) and that was already correct
   regardless of topology (see previous version of this doc, before this
   rewrite, for confirmation this part was never broken).
4. Fix the `multiwoven-config.yaml` ConfigMap gating for
   `TEMPORAL_POSTGRES_USER`/`TEMPORAL_POSTGRES_PASSWORD` per the ‡ bug
   above — gate both on `secretsStore.temporalSecretEnabled` (not
   `secretsStore.enabled`) — and add the same treatment for a new
   `TEMPORAL_VISIBILITY_POSTGRES_USER`/`TEMPORAL_VISIBILITY_POSTGRES_PASSWORD`
   pair, same flag.
5. Give the server/worker/solid-worker Deployments an actual `secretKeyRef`
   for these when the flag is on — same shape as the existing `mw` block in
   [multiwoven-server-deployment.yaml](../templates/multiwoven-server-deployment.yaml),
   just pointed at the group that already exists:
   ```yaml
   {{ if .Values.secretsStore.temporalSecretEnabled }}
   - name: TEMPORAL_POSTGRES_USER
     valueFrom:
       secretKeyRef:
         name: {{ .Values.secretsStore.temporalSecretAlias }}
         key: TP_DB_USERNAME
   - name: TEMPORAL_POSTGRES_PASSWORD
     valueFrom:
       secretKeyRef:
         name: {{ .Values.secretsStore.temporalSecretAlias }}
         key: TP_DB_PASSWORD
   {{ end }}
   ```

**No new AWS secret, no new `SecretProviderClass` needed for this.** The
`temporal` group's synced Secret already carries `TP_DB_USERNAME`/
`TP_DB_PASSWORD` — this just points a second consumer at it. That's the
whole point of the streamline: credentials are sourced from one place
(the `temporal`/`temporal-visibility` groups) whether the topology is
single-host or split-host, and `multipleDbHosts` goes back to being purely
about hosts and names.

**Deliberately not changed:** the single-host default path (`{{ if not
.Values.multipleDbHosts.enabled }}`) currently falls back to *reusing* the
`mw` credentials (`DB_USERNAME`/`DB_PASSWORD` from the shared ConfigMap) for
Temporal's Postgres connection when `temporalSecretEnabled` is off — i.e. in
single-host mode, Temporal is assumed to share the same Postgres
instance/user as the main app, just a different database. Switching that to
also use the new canonical `temporalPostgresUser`/`temporalPostgresPassword`
fallback would be a behavior change for existing single-host installs that
have never set those fields (they'd suddenly get an empty password instead
of the previously-shared one). Flagging this as a call-out rather than
deciding it here — worth a separate conversation, not a silent side effect
of this migration.

## 3. Proposed design

Extend the existing AWS Secrets Manager + Secrets Store CSI pattern (§1.1) to
cover the values in §2, instead of inventing a new mechanism. Group by
**component**, matching how the ConfigMaps are already split, so each group
maps to one new AWS Secrets Manager secret, one new `SecretProviderClass`,
and one synced `Secret`.

### 3.1 Groups

| Group | Covers | New AWS secret (example name) | Consumed by |
|---|---|---|---|
| `app` | §2.1 core app secrets (not Temporal DB creds — see §2.5) | `<env>-multiwoven/app` | server, worker, solid-worker |
| `sandbox` | §2.2 agentic coding / registry | `<env>-multiwoven/sandbox` | server, worker, solid-worker |
| `box` | §2.3 box API key/encryption key (DB creds already covered conceptually, fold in here) | `<env>-multiwoven/box` | box |
| `lightning` | §2.4 model gateway API keys | `<env>-multiwoven/lightning` | lightning |

The `<env>-` prefix (`dev-multiwoven/app`, `staging-multiwoven/app`, ...) is
required, not cosmetic, whenever more than one environment shares an AWS
account — see the IAM note in §4. Since IAM role/policy names are
account-global, an unprefixed name is a namespace collision waiting to
happen the moment a second environment's setup runs in the same account.

Temporal's DB credentials (`temporalPostgresUser`/`temporalPostgresPassword`,
`temporalVisibilityPostgresUser`/`temporalVisibilityPostgresPassword`) are
**not** a fifth group here — they're already served by the pre-existing
`temporal`/`temporal-visibility` groups from §1.1. §2.5 covers extending
that existing wiring rather than inventing a new one.

Splitting further (e.g. one secret per lightning backend) would mean 11
SecretProviderClasses for lightning alone with no operational benefit — one
secret per *consuming Deployment* is the right granularity, same as today's
per-database-role split.

### 3.2 `values.yaml` additions

Follow the exact naming convention already used under `secretsStore:`:

```yaml
secretsStore:
  # existing keys unchanged...

  appSecretEnabled: false
  appSecretAlias: multiwoven-app-f01dd256e712
  AppCredsSecretName: ""

  sandboxSecretEnabled: false
  sandboxSecretAlias: multiwoven-sandbox-f01dd256e712
  SandboxCredsSecretName: ""

  boxSecretEnabled: false
  boxSecretAlias: multiwoven-box-f01dd256e712
  BoxCredsSecretName: ""

  lightningSecretEnabled: false
  lightningSecretAlias: multiwoven-lightning-f01dd256e712
  LightningCredsSecretName: ""
```

Each flag defaults to `false` so existing installs are unaffected until an
operator opts in per group, exactly like `tempStoreSecretEnabled` /
`temporalSecretEnabled` do today.

### 3.3 `SecretProviderClass` templates

One new file per group, same shape as
[multiwoven-secret-provider-class-mw.yaml](../templates/multiwoven-secret-provider-class-mw.yaml).
Because these groups have many keys (not just `u`/`p`), name the `jmesPath`
aliases after the target env var directly rather than inventing short codes
— there's no reuse pressure like the DB case had. The `jmesPath` **source**
(`path:`), in turn, matches the field's existing `values.yaml` key name
(e.g. `awsAccessKeyId`, not a re-invented `aws_access_key_id`) — the AWS
secret's JSON is then a 1:1 mirror of the `values.yaml` block it's replacing,
so there's exactly one naming scheme to keep in your head, not three
(`values.yaml` key → env var → AWS secret field, each spelled differently):

`templates/multiwoven-secret-provider-class-app.yaml`:

```yaml
{{ if .Values.secretsStore.appSecretEnabled }}
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: {{ include "chart.fullname" . }}-secret-provider-class-app
  namespace: {{ .Values.kubernetesNamespace }}
  labels:
    app: {{ include "chart.fullname" . }}-secret-provider-class-app
    io.kompose.service: {{ include "chart.fullname" . }}-secret-provider-class-app
    {{- include "chart.labels" . | nindent 4 }}
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: {{ required "AppCredsSecretName is required" .Values.secretsStore.AppCredsSecretName }}
        objectType: secretsmanager
        jmesPath:
          - path: awsAccessKeyId
            objectAlias: AWS_ACCESS_KEY_ID
          - path: awsSecretAccessKey
            objectAlias: AWS_SECRET_ACCESS_KEY
          - path: appsignalPushApiKey
            objectAlias: APPSIGNAL_PUSH_API_KEY
          - path: boxApiKey
            objectAlias: BOX_API_KEY
          - path: codeExecSigningSecret
            objectAlias: CODE_EXEC_SIGNING_SECRET
          - path: hostedVectorDbUsername
            objectAlias: HOSTED_VECTOR_DB_USERNAME
          - path: hostedVectorDbPassword
            objectAlias: HOSTED_VECTOR_DB_PASSWORD
          - path: hubspotApiKey
            objectAlias: HUBSPOT_API_KEY
          - path: jwtSecret
            objectAlias: JWT_SECRET
          - path: maxmindLicenseKey
            objectAlias: MAXMIND_LICENSE_KEY
          - path: neonApiKey
            objectAlias: NEON_API_KEY
          - path: openrouterApiKey
            objectAlias: OPENROUTER_API_KEY
          - path: p2wLlmApiKey
            objectAlias: P2W_LLM_API_KEY
          - path: prometheusMetricsUsername
            objectAlias: PROMETHEUS_METRICS_USERNAME
          - path: prometheusMetricsPassword
            objectAlias: PROMETHEUS_METRICS_PASSWORD
          - path: promptToWorkflowApiKey
            objectAlias: PROMPT_TO_WORKFLOW_API_KEY
          - path: secretKeyBase
            objectAlias: SECRET_KEY_BASE
          - path: smtpUsername
            objectAlias: SMTP_USERNAME
          - path: smtpPassword
            objectAlias: SMTP_PASSWORD
          - path: storageAccessKey
            objectAlias: STORAGE_ACCESS_KEY
          - path: textractAccessKeyId
            objectAlias: TEXTRACT_ACCESS_KEY_ID
          - path: textractSecretAccessKey
            objectAlias: TEXTRACT_SECRET_ACCESS_KEY
  secretObjects:
  - secretName: {{ .Values.secretsStore.appSecretAlias }}
    type: Opaque
    data:
      - objectName: AWS_ACCESS_KEY_ID
        key: AWS_ACCESS_KEY_ID
      - objectName: AWS_SECRET_ACCESS_KEY
        key: AWS_SECRET_ACCESS_KEY
      - objectName: APPSIGNAL_PUSH_API_KEY
        key: APPSIGNAL_PUSH_API_KEY
      - objectName: BOX_API_KEY
        key: BOX_API_KEY
      - objectName: CODE_EXEC_SIGNING_SECRET
        key: CODE_EXEC_SIGNING_SECRET
      - objectName: HOSTED_VECTOR_DB_USERNAME
        key: HOSTED_VECTOR_DB_USERNAME
      - objectName: HOSTED_VECTOR_DB_PASSWORD
        key: HOSTED_VECTOR_DB_PASSWORD
      - objectName: HUBSPOT_API_KEY
        key: HUBSPOT_API_KEY
      - objectName: JWT_SECRET
        key: JWT_SECRET
      - objectName: MAXMIND_LICENSE_KEY
        key: MAXMIND_LICENSE_KEY
      - objectName: NEON_API_KEY
        key: NEON_API_KEY
      - objectName: OPENROUTER_API_KEY
        key: OPENROUTER_API_KEY
      - objectName: P2W_LLM_API_KEY
        key: P2W_LLM_API_KEY
      - objectName: PROMETHEUS_METRICS_USERNAME
        key: PROMETHEUS_METRICS_USERNAME
      - objectName: PROMETHEUS_METRICS_PASSWORD
        key: PROMETHEUS_METRICS_PASSWORD
      - objectName: PROMPT_TO_WORKFLOW_API_KEY
        key: PROMPT_TO_WORKFLOW_API_KEY
      - objectName: SECRET_KEY_BASE
        key: SECRET_KEY_BASE
      - objectName: SMTP_USERNAME
        key: SMTP_USERNAME
      - objectName: SMTP_PASSWORD
        key: SMTP_PASSWORD
      - objectName: STORAGE_ACCESS_KEY
        key: STORAGE_ACCESS_KEY
      - objectName: TEXTRACT_ACCESS_KEY_ID
        key: TEXTRACT_ACCESS_KEY_ID
      - objectName: TEXTRACT_SECRET_ACCESS_KEY
        key: TEXTRACT_SECRET_ACCESS_KEY
{{ end }}
```

`multiwoven-secret-provider-class-sandbox.yaml`, `-box.yaml`, and
`-lightning.yaml` follow the same shape for the keys in §2.2–§2.4.

The corresponding AWS Secrets Manager secret (`<env>-multiwoven/app`, e.g.
`dev-multiwoven/app`) is one JSON object with matching field names, e.g.:

```json
{
  "awsAccessKeyId": "...",
  "awsSecretAccessKey": "...",
  "appsignalPushApiKey": "...",
  "jwtSecret": "...",
  "secretKeyBase": "...",
  "smtpUsername": "...",
  "smtpPassword": "..."
}
```

### 3.4 Deployment wiring

Two changes per consuming Deployment, mirroring the volume/env split already
used for the DB creds:

1. **Volume mount** — add a CSI volume per enabled group (only actually
   needed for the sync side-effect, same as today):
   ```yaml
   {{ if .Values.secretsStore.appSecretEnabled }}
   - name: multiwoven-app-secrets-store
     csi:
       driver: secrets-store.csi.k8s.io
       readOnly: true
       volumeAttributes:
         secretProviderClass: {{ include "chart.fullname" . }}-secret-provider-class-app
   {{ end }}
   ```
2. **Env vars** — with 20+ keys per group, prefer `envFrom.secretRef` over
   repeating `secretKeyRef` for every single key. This is a deliberate
   deviation from the DB pattern (which uses `secretKeyRef` because it's only
   2 keys) but consistent with how this chart already pulls the ConfigMap in
   bulk via `envFrom.configMapRef`:
   ```yaml
   envFrom:
   - configMapRef:
       name: {{ include "chart.fullname" . }}-config
   {{ if .Values.secretsStore.appSecretEnabled }}
   - secretRef:
       name: {{ .Values.secretsStore.appSecretAlias }}
   {{ end }}
   ```
   This requires the synced Secret's keys to exactly match the env var names
   the app expects, which they do by construction in §3.3.

### 3.5 ConfigMap fallback

In each ConfigMap, gate the plaintext keys behind `{{ if not
.Values.secretsStore.<group>SecretEnabled }}`, exactly like `DB_PASSWORD` is
gated today, so `values.yaml` literals remain the fallback for
community/local installs that don't have Secrets Manager wired up:

```yaml
{{ if not .Values.secretsStore.appSecretEnabled }}
JWT_SECRET: {{ .Values.multiwovenConfig.jwtSecret | quote }}
SECRET_KEY_BASE: {{ .Values.multiwovenConfig.secretKeyBase | quote }}
# ...rest of the app-group keys
{{ end }}
```

Do this key-by-key for every entry listed in §2.1–§2.4, moved out of the
unconditional `data:` block into the guarded block for its group.

`temporalPostgresUser`/`temporalPostgresPassword` are **not** part of this
`appSecretEnabled` guard, despite living in the same `multiwovenConfig`
values block and the same `multiwoven-config.yaml` ConfigMap as the keys
above — see §2.5 for why they get gated on `secretsStore.temporalSecretEnabled`
and reuse the pre-existing `temporal` group instead.

## 4. IAM

The pod's service account (`serviceAccount.annotations."eks.amazonaws.com/role-arn"`
in `values.yaml`) needs `secretsmanager:GetSecretValue` on the new secret
ARNs (`<env>-multiwoven/app`, `<env>-multiwoven/sandbox`,
`<env>-multiwoven/box`, `<env>-multiwoven/lightning`), same as it presumably
already has for the four existing `*CredsSecretName` secrets. This is IAM
policy managed outside the chart, but each group's `CredsSecretName` value
should resolve to an ARN covered by that policy before
`secretsStore.<group>SecretEnabled` is flipped to `true` in an environment —
the CSI mount will fail closed with an `AccessDenied` if not, which will
fail pod scheduling for that Deployment.

**If this AWS account hosts more than one environment for this chart**
(common — dev/qa/staging/prod sharing one account, sometimes even sharing
one EKS cluster split only by namespace, as `qa`/`staging` do in at least
one real deployment of this chart): the IAM **role and policy names**, not
just the secret names, must be environment-prefixed too. Role/policy names
are account-global — `multiwoven-pod-role` created for dev and
`multiwoven-pod-role` created for staging in the same account is a straight
collision (second `create-role` call fails, or worse, someone "fixes" the
error by reusing the first role, silently granting staging's pods dev's
permissions). `dev-multiwoven-pod-role` / `staging-multiwoven-pod-role` — or
your own equivalent scheme — avoids this. The K8s ServiceAccount *name*
doesn't need the same treatment: it's namespaced, and the IAM trust policy
is scoped per cluster-OIDC-provider + namespace + SA-name already, so
identically-named ServiceAccounts in different namespaces/clusters can't
assume each other's role. See SECRETS_IMPLEMENTATION.md §0.3 for the actual
`eksctl`/policy commands, including the fact that `eksctl create
iamserviceaccount` requires the policy to exist *before* the role is
created — there's no create-then-attach-later flow with that tool.

## 5. Rollout plan (per environment, per group)

1. Create the AWS Secrets Manager secret with the JSON shape from §3.3.
2. Grant the environment's pod IAM role `secretsmanager:GetSecretValue` on it.
3. Set `secretsStore.<group>SecretEnabled: true` and
   `secretsStore.<Group>CredsSecretName` in that environment's values
   override.
4. Deploy, then verify: the synced Secret exists (`kubectl get secret
   <alias>`), the pod's env has the values (`kubectl exec ... -- env | grep
   ...` against a non-prod pod only), and the app functions.
5. Once verified, remove the now-unused plaintext values for that group from
   the environment's values override (they still exist in the chart's
   default `values.yaml` as the community-install fallback — only the
   per-environment override should drop them).
6. Repeat per group; groups are independent so this can land incrementally
   (e.g. `app` first, `lightning` last) rather than as one big-bang cutover.

## 6. Out of scope / follow-ups

- Secret **rotation** — the CSI driver only re-syncs the mounted files /
  synced Secret on its polling interval, and even then a running pod's
  `secretKeyRef`/`envFrom.secretRef` env vars won't pick up the change
  without a restart. See
  [SECRETS_IMPLEMENTATION.md](SECRETS_IMPLEMENTATION.md) Phase 7
  (rotation reconciler + Reloader-triggered rolling restarts) for the plan.
- `registrySecretName` (§1.2) stays as-is: it's a pre-existing Secret
  referenced by name, not something this chart should start templating.
- `viteAppsignalPushApiKey` (§2.1) stays a plain ConfigMap value by design,
  not because it was missed — see §2.1 for why.
