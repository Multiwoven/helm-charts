# Implementing Secret-Backed Config: Step-by-Step

This is the execution runbook for the design in [SECRETS.md](SECRETS.md).
Read that first for the "why" — this doc is just the ordered "how."

Work through the phases in order. Phase 3 (chart changes) can be done once
for all four groups, but phases 4–6 (rollout) should be done **one group at
a time**, starting with a non-prod environment, so a bad value in one group
doesn't take down every component at once.

Groups, recap: `app`, `sandbox`, `box`, `lightning` — see SECRETS.md §2 for
which keys belong to each. Phase 3 also includes one item (§3.4) that isn't
a new group at all: streamlining `multipleDbHosts` so it goes back to being
pure host/database-name config, with Temporal's DB credentials sourced from
the pre-existing `temporal` group instead of living inside `multipleDbHosts`
itself. That one ships as a values.yaml rename, not a new opt-in flag — see
§3.4 for the upgrade note that matters if any environment already has
`multipleDbHosts.enabled: true`.

## Phase 0 — Prerequisites (cluster-level, one-time)

All three items below are cluster-level, outside this chart — this chart
only ever grants RBAC to a driver it assumes already exists
([multiwoven-cluster-role.yaml](../templates/multiwoven-cluster-role.yaml)
binds to `ServiceAccount secrets-store-csi-driver` in `kube-system`). Check
each; only do the "if not" steps for whichever ones are actually missing.

### 0.1 Secrets Store CSI Driver + AWS provider

**Check:**
```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws
kubectl get crd secretproviderclasses.secrets-store.csi.x-k8s.io
```
If all three return results, the driver and provider are installed — skip
to 0.2. If any is empty, install:

```bash
# 1. The driver itself
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update
helm install csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true \
  --set enableSecretRotation=true \
  --set rotationPollInterval=2m

# 2. The AWS provider (a separate DaemonSet, installed via manifest, not Helm)
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml
```

`--set syncSecret.enabled=true` is not optional — without it, the driver
mounts the CSI volume but never populates `secretObjects` into a real
Kubernetes `Secret`, so every `secretKeyRef` in this chart resolves to
nothing and every affected pod fails to start. This is the single most
common reason the existing `mw`/`temp-store`/`temporal` groups don't work
on a cluster that "has the driver" but was installed by someone who didn't
know this flag existed. `enableSecretRotation`/`rotationPollInterval` here
just get Phase 0.2 out of the way in the same install — set them now even
though nothing in Phases 1–6 depends on them yet.

Verify after install:
```bash
kubectl get pods -n kube-system -l app=secrets-store-csi-driver -w
kubectl get pods -n kube-system -l app=csi-secrets-store-provider-aws -w
```
Wait for `Running`/`1/1` on both before moving on — a driver pod stuck in
`CrashLoopBackOff` here means every later phase's pods will fail to mount.

### 0.2 Rotation reconciler

**Check** (only relevant if the driver was already installed by someone
else before 0.1):
```bash
kubectl get daemonset -n kube-system -l app=secrets-store-csi-driver -o jsonpath='{.items[0].spec.template.spec.containers[0].args}'
```
Look for `--enable-secret-rotation=true` and `--rotation-poll-interval=...`
in the output. If present, skip ahead — if you just did a fresh install via
0.1's `helm install` command, this is already done.

**If not:**
```bash
# if the driver was installed via Helm
helm upgrade csi-secrets-store secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --reuse-values \
  --set enableSecretRotation=true \
  --set rotationPollInterval=2m

# if it was installed via raw manifests instead of Helm
kubectl -n kube-system patch daemonset csi-secrets-store-secrets-store-csi-driver \
  --type='json' \
  -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--enable-secret-rotation=true"}, {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--rotation-poll-interval=2m"}]'
```
Confirm the daemonset rolled out (`kubectl rollout status daemonset
csi-secrets-store-secrets-store-csi-driver -n kube-system`) before treating
this as done. Not a blocker for Phases 1–6 — only needed for Phase 7.

### 0.3 Pod service account IAM role

**Check:**
```bash
kubectl get sa multiwoven-service-account -n multiwoven -o jsonpath='{.metadata.annotations}'
```
Note the `eks.amazonaws.com/role-arn` value, then:
```bash
aws iam get-role --role-name <role-name-from-the-arn-above>
```
If that returns a role (not `NoSuchEntity`), it exists — skip to Phase 1.
**Check the chart's default carefully first**: `values.yaml`'s
`serviceAccount.annotations` ships with a placeholder —
`arn:aws:iam::123456789012:role/example-role` — which will pass the
`kubectl get sa` check (the annotation exists) but fail the `aws iam
get-role` check (account `123456789012` isn't real). Don't stop at "the
annotation is set"; confirm the role actually resolves in your AWS account.

**If not**, create it via IRSA (IAM Roles for Service Accounts — requires
the cluster already have an OIDC provider associated, which most EKS
clusters set up at creation; `eksctl utils associate-iam-oidc-provider` if
not).

**Before running `eksctl`, know two things about your AWS account layout —
both change what "the role name" and "the secret names" need to be:**

1. **`eksctl create iamserviceaccount` requires `--attach-policy-arn` or
   `--attach-role-arn` up front.** There is no "create a bare role, attach
   permissions in a later phase" mode — that's not a simplification this
   doc gets to make, it's a hard requirement of the tool. So the IAM policy
   from Phase 2 has to exist *before* this step, not after it. Since actual
   secret ARNs don't exist yet at this point (Phase 1 hasn't run), scope the
   policy to a name *prefix* you commit to now rather than exact ARNs — see
   the policy JSON below.
2. **If this AWS account hosts more than one environment for this chart**
   (dev/qa/staging/prod sharing one account — extremely common, and true for
   at least one real deployment of this chart, where qa and staging even
   share the *same EKS cluster*, split only by namespace), then IAM role
   names and policy names — which are account-global, not per-cluster or
   per-namespace — **must** be environment-prefixed, or two environments'
   setups will collide or silently reuse each other's role. The K8s
   ServiceAccount name does *not* need this prefix — it's namespaced, and
   `eksctl` scopes the trust policy to the specific
   cluster-OIDC-provider + namespace + SA-name triple, so identically-named
   SAs in different namespaces/clusters can't assume each other's role.

```bash
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="us-east-1"
ENV="dev"   # dev | qa | staging | prod — whichever this run is for
POLICY_NAME="${ENV}-multiwoven-secrets-read"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  POLICY_ARN="$(aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [{
        "Effect": "Allow",
        "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
        "Resource": "arn:aws:secretsmanager:'"$REGION"':'"$ACCOUNT_ID"':secret:'"$ENV"'-multiwoven/*"
      }]
    }' \
    --query "Policy.Arn" --output text)"
fi

eksctl create iamserviceaccount \
  --cluster <your-cluster-name> \
  --namespace multiwoven \
  --name multiwoven-service-account \
  --role-name "${ENV}-multiwoven-pod-role" \
  --attach-policy-arn "$POLICY_ARN" \
  --override-existing-serviceaccounts \
  --approve
```

This creates the IAM policy (scoped to the `<env>-multiwoven/*` secret-name
prefix — matches Phase 1's naming below), the IAM role and trust policy
(scoped to `system:serviceaccount:multiwoven:multiwoven-service-account` on
this specific cluster), attaches the policy to the role, and annotates the
K8s ServiceAccount for you, all in one step — Phase 2 for this chart is then
just a double-check that Phase 1's actual secret names landed inside the
prefix this policy grants, not a separate attachment step. Then set
`serviceAccount.create: false` and update
`serviceAccount.annotations."eks.amazonaws.com/role-arn"` in your values
override to the role ARN `eksctl` printed, replacing the chart's
placeholder.

If you'd rather do it without `eksctl` (e.g. no local install, or your org
manages IAM via Terraform/CloudFormation instead), the equivalent manual
steps are: create the policy above via `aws iam create-policy`, get the
cluster's OIDC provider URL (`aws eks describe-cluster --name <cluster>
--query "cluster.identity.oidc.issuer"`), write a trust policy JSON scoped
to that provider + `multiwoven:multiwoven-service-account`, `aws iam
create-role` with it, then `aws iam attach-role-policy` — `eksctl` above is
just doing all of these calls for you.

## Phase 1 — Create the AWS Secrets Manager secrets

Create one JSON secret per group, named `<env>-multiwoven/<group>` — the
`<env>-` prefix matches the IAM policy scoped in Phase 0.3, and is required
(not optional) whenever this account hosts more than one environment for
this chart, which is the common case, not the exception. Field names match
the corresponding `values.yaml` key exactly (e.g. `awsAccessKeyId`, not a
re-invented `aws_access_key_id`) — they become the `jmesPath` source paths
in Phase 3, so this is the one place you need to spell each field, not
three.

```bash
ENV="dev"   # dev | qa | staging | prod — whichever this run is for

aws secretsmanager create-secret --name "${ENV}-multiwoven/app" --secret-string '{
  "awsAccessKeyId": "",
  "awsSecretAccessKey": "",
  "appsignalPushApiKey": "",
  "boxApiKey": "",
  "codeExecSigningSecret": "",
  "hostedVectorDbUsername": "",
  "hostedVectorDbPassword": "",
  "hubspotApiKey": "",
  "jwtSecret": "",
  "maxmindLicenseKey": "",
  "neonApiKey": "",
  "openrouterApiKey": "",
  "p2wLlmApiKey": "",
  "prometheusMetricsUsername": "",
  "prometheusMetricsPassword": "",
  "promptToWorkflowApiKey": "",
  "secretKeyBase": "",
  "smtpUsername": "",
  "smtpPassword": "",
  "storageAccessKey": "",
  "textractAccessKeyId": "",
  "textractSecretAccessKey": ""
}'

aws secretsmanager create-secret --name "${ENV}-multiwoven/sandbox" --secret-string '{
  "agenticCodingBuildToken": "",
  "codingAgentModelApiKey": "",
  "modalTokenId": "",
  "modalTokenSecret": "",
  "dockerHubRegistryUsername": "",
  "dockerHubRegistryPassword": ""
}'

aws secretsmanager create-secret --name "${ENV}-multiwoven/box" --secret-string '{
  "boxApiKey": "",
  "boxEncryptionKey": "",
  "dbUsername": "",
  "dbPassword": ""
}'

aws secretsmanager create-secret --name "${ENV}-multiwoven/lightning" --secret-string '{
  "babelApiKey": "",
  "polyApiKey": "",
  "chatApiKey": "",
  "embeddingApiKey": "",
  "judyApiKey": "",
  "multimodalChatApiKey": "",
  "pathfinderApiKey": "",
  "seemoreApiKey": "",
  "sentinelApiKey": "",
  "structuredExtractionApiKey": "",
  "xpertApiKey": ""
}'
```

- [ ] Fill in real values (or rotate them in immediately after creation —
      don't leave real secrets in shell history / `create-secret` CLI args
      for longer than necessary; consider `--secret-string file://path.json`
      with the file shredded after).
- [ ] Repeat per environment — each of dev/qa/staging/prod gets its own
      `<env>-multiwoven/<group>` secret, even the ones that happen to share
      an AWS account. Don't reuse one secret across environments just
      because the account is shared; that's exactly what the `<env>-` prefix
      exists to prevent.

## Phase 2 — IAM

- [ ] Confirm each secret created in Phase 1 actually landed inside the
      `<env>-multiwoven/*` prefix the Phase 0.3 policy was scoped to — a
      typo here (e.g. `multiwoven-app` instead of `dev-multiwoven/app`)
      produces `AccessDenied` at pod-mount time with no obvious link back to
      the typo:
      ```bash
      aws secretsmanager list-secrets --query "SecretList[].Name" --output text | tr '\t' '\n' | grep multiwoven
      ```
- [ ] If the policy from 0.3 was scoped more narrowly than a prefix wildcard
      (e.g. exact ARNs, decided before Phase 1 existed), update it now with
      the ARNs Phase 1 actually returned — `aws iam create-policy-version`
      with `--set-as-default`, since policies aren't mutable in place.
- [ ] Double check `kms:Decrypt` permissions if the secrets use a
      customer-managed KMS key rather than the default AWS-managed one —
      not covered by the Phase 0.3 policy above, which only grants
      `secretsmanager:*`.

## Phase 3 — Chart changes

Do this once; it's environment-agnostic. All edits are relative to
`charts/multiwoven/`.

### 3.1 `values.yaml`

Add to the existing `secretsStore:` block:

```yaml
secretsStore:
  # ...existing keys unchanged...

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

### 3.2 New `SecretProviderClass` templates

Create these four files under `templates/`. Use
[multiwoven-secret-provider-class-mw.yaml](../templates/multiwoven-secret-provider-class-mw.yaml)
as the structural reference. Full `app`-group example (copy this shape for
the other three, substituting the key list from SECRETS.md §2.2–§2.4):

`templates/multiwoven-secret-provider-class-app.yaml` — see SECRETS.md §3.3
for the complete file contents; don't retype it here, copy it from there.

`templates/multiwoven-secret-provider-class-sandbox.yaml`,
`templates/multiwoven-secret-provider-class-box.yaml`,
`templates/multiwoven-secret-provider-class-lightning.yaml` — same shape,
using the field names from Phase 1's JSON and the env var names from
SECRETS.md §2.2–§2.4.

- [ ] Every `objectAlias` in `jmesPath` and every `objectName`/`key` pair in
      `secretObjects` must match, and must match the env var name the app
      actually expects (they're the same string by construction if you
      follow the naming above).
- [ ] Run `helm template charts/multiwoven --set secretsStore.appSecretEnabled=true --set secretsStore.AppCredsSecretName=dev-multiwoven/app` (repeat per group) and diff the output against expectations before moving on.

### 3.3 Gate the plaintext ConfigMap keys

For each group, wrap its keys in `templates/multiwoven-config.yaml`,
`templates/box-config.yaml`, or `templates/lightning-config.yaml` in an
`{{ if not .Values.secretsStore.<group>SecretEnabled }} ... {{ end }}` block,
same as `DB_PASSWORD` is handled today. Example for the `app` group in
`multiwoven-config.yaml` — move these lines (currently unconditional) inside
the guard:

```yaml
{{ if not .Values.secretsStore.appSecretEnabled }}
AWS_ACCESS_KEY_ID: {{ .Values.multiwovenConfig.awsAccessKeyId | quote }}
AWS_SECRET_ACCESS_KEY: {{ .Values.multiwovenConfig.awsSecretAccessKey | quote }}
APPSIGNAL_PUSH_API_KEY: {{ .Values.multiwovenConfig.appsignalPushApiKey | quote }}
BOX_API_KEY: {{ .Values.multiwovenConfig.boxApiKey | quote }}
CODE_EXEC_SIGNING_SECRET: {{ .Values.multiwovenConfig.codeExecSigningSecret | quote }}
HOSTED_VECTOR_DB_USERNAME: {{ .Values.multiwovenConfig.hostedVectorDbUsername | quote }}
HOSTED_VECTOR_DB_PASSWORD: {{ .Values.multiwovenConfig.hostedVectorDbPassword | quote }}
HUBSPOT_API_KEY: {{ .Values.multiwovenConfig.hubspotApiKey | quote }}
JWT_SECRET: {{ .Values.multiwovenConfig.jwtSecret | quote }}
MAXMIND_LICENSE_KEY: {{ .Values.multiwovenConfig.maxmindLicenseKey | quote }}
NEON_API_KEY: {{ .Values.multiwovenConfig.neonApiKey | quote }}
OPENROUTER_API_KEY: {{ .Values.multiwovenConfig.openrouterApiKey | quote }}
P2W_LLM_API_KEY: {{ .Values.multiwovenConfig.p2wLlmApiKey | quote }}
PROMETHEUS_METRICS_USERNAME: {{ .Values.multiwovenConfig.prometheusMetricsUsername | quote }}
PROMETHEUS_METRICS_PASSWORD: {{ .Values.multiwovenConfig.prometheusMetricsPassword | quote }}
PROMPT_TO_WORKFLOW_API_KEY: {{ .Values.multiwovenConfig.promptToWorkflowApiKey | quote }}
SECRET_KEY_BASE: {{ .Values.multiwovenConfig.secretKeyBase | quote }}
SMTP_USERNAME: {{ .Values.multiwovenConfig.smtpUsername | quote }}
SMTP_PASSWORD: {{ .Values.multiwovenConfig.smtpPassword | quote }}
STORAGE_ACCESS_KEY: {{ .Values.multiwovenConfig.storageAccessKey }}
TEXTRACT_ACCESS_KEY_ID: {{ .Values.multiwovenConfig.textractAccessKeyId | quote }}
TEXTRACT_SECRET_ACCESS_KEY: {{ .Values.multiwovenConfig.textractSecretAccessKey | quote }}
{{ end }}
```

`temporalPostgresUser`/`temporalPostgresPassword` are **not** part of this
`appSecretEnabled` block — they get their own fix in §3.4, reusing the
pre-existing `temporal` group instead of the new `app` one.

Do the same for the `sandbox` group's keys (also in `multiwoven-config.yaml`,
gated on `sandboxSecretEnabled`), the `box` group's keys (in
`box-config.yaml`, gated on `boxSecretEnabled`), and the `lightning` group's
keys (in `lightning-config.yaml`, gated on `lightningSecretEnabled`).

- [ ] Leave every other (non-sensitive) key in each ConfigMap unconditional —
      don't over-gate.

### 3.4 Streamline `multipleDbHosts` and Temporal DB credentials

This is a separate fix from the four groups above — no new AWS secret, no
new `SecretProviderClass`. It reuses the `temporal` group that already
exists (§1.1), and removes credential values that currently live inside
`multipleDbHosts`, which should only ever hold host/database-name overrides
for its one edge case (an operator whose managed Postgres allows only one
database per instance, so `multiwoven`/`temporal`/`temporal-visibility` each
need a different host). See SECRETS.md §2.5 for the full rationale.

- [ ] In `values.yaml`, add to `multiwovenConfig`:
  ```yaml
  temporalVisibilityPostgresUser: ""
  temporalVisibilityPostgresPassword: ""
  ```
  (`temporalPostgresUser`/`temporalPostgresPassword` already exist — they're
  being put to actual use for the first time, not renamed.)
- [ ] Remove from `multipleDbHosts`: `temporalDbUsername`, `temporalDbPassword`,
      `temporalVisibilityDbUsername`, `temporalVisibilityDbPassword`. It should
      end up holding only `enabled`, `multiwovenDBHost`, `multiwovenDBName`,
      `temporalDbName`, `temporalDbHost`, `temporalVisibilityDbName`,
      `temporalVisibilityDbHost`.
- [ ] **This is a breaking values.yaml rename for anyone already running
      `multipleDbHosts.enabled: true`.** Before merging, check every
      environment's values override:
      ```bash
      grep -rn "temporalDbUsername\|temporalDbPassword\|temporalVisibilityDbUsername\|temporalVisibilityDbPassword" <environment-values-repo>
      ```
      Any hit needs to move to the new `multiwovenConfig.temporalPostgresUser` /
      `temporalPostgresPassword` / `temporalVisibilityPostgresUser` /
      `temporalVisibilityPostgresPassword` keys in the same PR that upgrades
      the chart version, or that environment silently falls back to an empty
      password on upgrade.
- [ ] In `multiwoven-config.yaml`, fix the existing gating (currently
      `secretsStore.enabled`, wrong flag — see SECRETS.md §2.1's ‡ note) and
      add the new visibility pair, all four gated on the same flag that
      already governs both the `temporal` and `temporal-visibility`
      SecretProviderClasses:
  ```yaml
  {{ if not .Values.secretsStore.temporalSecretEnabled }}
  TEMPORAL_POSTGRES_USER: {{ .Values.multiwovenConfig.temporalPostgresUser | quote }}
  TEMPORAL_POSTGRES_PASSWORD: {{ .Values.multiwovenConfig.temporalPostgresPassword | quote }}
  TEMPORAL_VISIBILITY_POSTGRES_USER: {{ .Values.multiwovenConfig.temporalVisibilityPostgresUser | quote }}
  TEMPORAL_VISIBILITY_POSTGRES_PASSWORD: {{ .Values.multiwovenConfig.temporalVisibilityPostgresPassword | quote }}
  {{ end }}
  ```
- [ ] In `multiwoven-server-deployment.yaml`, `multiwoven-worker-deployment.yaml`,
      and `multiwoven-solid-worker-deployment.yaml`, extend the existing
      `{{ if .Values.secretsStore.enabled }}` env block (the one already
      providing `DB_PASSWORD`/`DB_USERNAME` from the `mw` group) with a
      sibling block reusing the `temporal` group — same secret, same keys
      Temporal's own deployment already reads:
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
  - name: TEMPORAL_VISIBILITY_POSTGRES_USER
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secretsStore.temporalVisibilitySecretAlias }}
        key: TPV_DB_USERNAME
  - name: TEMPORAL_VISIBILITY_POSTGRES_PASSWORD
    valueFrom:
      secretKeyRef:
        name: {{ .Values.secretsStore.temporalVisibilitySecretAlias }}
        key: TPV_DB_PASSWORD
  {{ end }}
  ```
  No new `volumes`/`volumeMounts` entry needed here — these three
  Deployments don't need the CSI sync side-effect themselves, they just read
  the Secret that Temporal's own Deployment already triggers a sync for.
  That does mean the Temporal Deployment must be deployed/synced at least
  once with `temporalSecretEnabled: true` before these three start relying
  on the Secret existing — sequence matters on first rollout, not on
  steady-state.
- [ ] In `temporal-deployment.yaml`, update the `multipleDbHosts.enabled`
      branch's plaintext fallbacks (`TEMPORAL_DEFAULT_USER`,
      `TEMPORAL_DEFAULT_PASSWORD`, `TEMPORAL_VISIBILITY_USER`,
      `TEMPORAL_VISIBILITY_PASSWORD`) to read from the new
      `multiwovenConfig` fields instead of the `multipleDbHosts` fields
      being removed. The `secretKeyRef` half of each is unchanged — already
      correct.
- [ ] `helm template` with `multipleDbHosts.enabled=true` both before and
      after, diff the rendered `temporal-deployment.yaml` output, confirm
      only the *source* of the plaintext fallback changed, not the
      resulting env var names or the secret-backed path.

### 3.5 Wire the Deployments

For each Deployment that consumes an affected ConfigMap, add a volume and an
`envFrom.secretRef`, gated on that group's flag:

| Deployment file | Group(s) to wire |
|---|---|
| `multiwoven-server-deployment.yaml` | `app`, `sandbox` |
| `multiwoven-worker-deployment.yaml` | `app`, `sandbox` |
| `multiwoven-solid-worker-deployment.yaml` | `app`, `sandbox` |
| `box-deployment.yaml` | `box` |
| `lightning-deployment.yaml` | `lightning` |

Pattern (using `app` on the server deployment as the example — repeat per
group/deployment from the table):

```yaml
envFrom:
- configMapRef:
    name: {{ include "chart.fullname" . }}-config
{{ if .Values.secretsStore.appSecretEnabled }}
- secretRef:
    name: {{ .Values.secretsStore.appSecretAlias }}
{{ end }}
{{ if .Values.secretsStore.sandboxSecretEnabled }}
- secretRef:
    name: {{ .Values.secretsStore.sandboxSecretAlias }}
{{ end }}
```

```yaml
volumes:
# ...existing volumes...
{{ if .Values.secretsStore.appSecretEnabled }}
- name: multiwoven-app-secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "chart.fullname" . }}-secret-provider-class-app
{{ end }}
{{ if .Values.secretsStore.sandboxSecretEnabled }}
- name: multiwoven-sandbox-secrets-store
  csi:
    driver: secrets-store.csi.k8s.io
    readOnly: true
    volumeAttributes:
      secretProviderClass: {{ include "chart.fullname" . }}-secret-provider-class-sandbox
{{ end }}
```

```yaml
volumeMounts:
# ...existing mounts...
{{ if .Values.secretsStore.appSecretEnabled }}
- name: multiwoven-app-secrets-store
  mountPath: /run/secrets/app-secrets
  readOnly: true
{{ end }}
{{ if .Values.secretsStore.sandboxSecretEnabled }}
- name: multiwoven-sandbox-secrets-store
  mountPath: /run/secrets/sandbox-secrets
  readOnly: true
{{ end }}
```

The volume mount is only there to trigger the CSI sync side-effect — the
actual env values come from `envFrom.secretRef`, same division of labor as
the existing DB-creds pattern.

- [ ] `box-deployment.yaml` and `lightning-deployment.yaml` gets only the
      `box` / `lightning` block respectively (single group each).
- [ ] Lint with `helm lint charts/multiwoven` and `helm template
      charts/multiwoven` after each file edit — cheap to catch a stray brace
      immediately rather than after the four-file group is done.

### 3.6 Commit

- [ ] `helm lint` clean, `helm template` output reviewed with each flag
      toggled on and off.
- [ ] Bump `Chart.yaml` `version` (this is a chart behavior change).
- [ ] PR review, merge to `main`.

## Phase 4 — Roll out one group at a time (non-prod first)

Repeat this whole phase per group (`app`, then `sandbox`, `box`,
`lightning`, in whatever order you're comfortable with), per environment:

1. [ ] In the environment's values override, set:
   ```yaml
   secretsStore:
     appSecretEnabled: true
     AppCredsSecretName: "dev-multiwoven/app"   # this environment's prefix
   ```
2. [ ] `helm upgrade` that environment.
3. [ ] Watch the rollout: `kubectl -n multiwoven get pods -w`. A CSI mount
       failure (bad ARN, missing IAM permission) shows up as the pod stuck
       in `ContainerCreating` — check `kubectl -n multiwoven describe pod
       <pod>` events for `FailedMount` / `AccessDenied`.

## Phase 5 — Verify

- [ ] Synced Secret exists: `kubectl -n multiwoven get secret
      <alias-from-values>`.
- [ ] Keys match expectations: `kubectl -n multiwoven get secret <alias> -o
      jsonpath='{.data}' | jq 'keys'` (don't dump values in a shared
      terminal/log).
- [ ] App functions: hit the relevant feature end-to-end (e.g. for `app`
      group, confirm SMTP/JWT/S3-backed flows still work; for `lightning`,
      confirm each model backend actually responds; for `box`, confirm
      sandbox provisioning works).
- [ ] No `FailedMount` / `AccessDenied` events across the affected
      Deployment's pods over a full rollout cycle.

## Phase 6 — Clean up plaintext

- [ ] Once a group is verified in an environment, remove that group's
      plaintext values from **that environment's values override** (not
      the chart's default `values.yaml` — the defaults stay as the
      no-Secrets-Manager community-install fallback).
- [ ] Repeat Phases 4–6 for the next group.
- [ ] Once all four groups are live everywhere that matters, consider
      whether the chart's default `values.yaml` placeholder values (several
      are already empty strings, a few like `dbPassword: password` are not)
      should be scrubbed of anything that looks like a real-looking default
      — but that's a separate, smaller cleanup from this migration.

## Phase 7 — Rotation (do after Phases 1–6 are stable)

This closes the gap described in SECRETS.md: rotating the value in Secrets
Manager alone does not update already-running pods, because env vars are
snapshotted at container start.

1. [ ] Confirm with the CSI driver's operator that
       `--enable-secret-rotation=true` is set (Phase 0) — without this nothing
       here works, the driver simply never re-fetches after initial mount.
2. [ ] Install [Reloader](https://github.com/stakater/Reloader) in the
       cluster if it isn't already (`helm install reloader
       stakater/reloader`), and confirm it can `watch`/`list` `Secret`
       objects in the `multiwoven` namespace (check its RBAC/ClusterRole).
3. [ ] Annotate each affected Deployment's pod template with the group's
       synced-secret alias, e.g. on `multiwoven-server-deployment.yaml`:
       ```yaml
       spec:
         template:
           metadata:
             annotations:
               secret.reloader.stakater.com/reload: "{{ .Values.secretsStore.appSecretAlias }},{{ .Values.secretsStore.sandboxSecretAlias }}"
       ```
       (comma-separated list if a Deployment consumes more than one group's
       secret). Do the analogous single-value annotation for
       `box-deployment.yaml` and `lightning-deployment.yaml`.
4. [ ] Test end-to-end in non-prod: rotate a test value directly in Secrets
       Manager, wait for the driver's poll interval, confirm the synced
       `Secret` updates (`kubectl get secret ... -o yaml`), then confirm
       Reloader triggers a rolling restart of the right Deployment
       (`kubectl rollout history deployment/<name>`).
5. [ ] Roll the annotation change out the same incremental,
       one-group-at-a-time way as Phases 4–6.
