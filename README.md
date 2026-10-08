# AI Squared Helm Charts

Helm charts for deploying the AI Squared platform.

## Quick install 

The chart's hostnames default to `example.com` placeholders and NGINX ingress is enabled by default, so set
hostnames on a domain you control (with DNS pointing at your ingress controller) before installing:

```yaml
# my-values.yaml
platformConfig:
  uiHost: app.your-domain.com
  apiHost: api.your-domain.com
  viteApiHost: api.your-domain.com     # API host the UI calls; usually the same as apiHost
  workerHost: worker.your-domain.com
  solidWorkerHost: solid.your-domain.com
  temporalUiHost: temporal.your-domain.com
  tlsAdminEmail: you@your-domain.com   # Let's Encrypt account email; example.com addresses are rejected
lightningConfig:
  lightningHealthHost: lightning.your-domain.com
```

```
helm repo add aisquared https://multiwoven.github.io/helm-charts
helm install aisquared aisquared/aisquared -f my-values.yaml
```

## Upgrading from the multiwoven chart

The chart was renamed from `multiwoven` to `aisquared` (0.117.0) and its values keys were renamed. It's served from the
same Helm repository. To upgrade an existing installation in place:

1. **Keep your resource names.** Set `nameOverride: multiwoven`. Without it, every resource is recreated under a new name.
2. **Rename your values keys.** The chart fails with a message naming the new key if an old one is used.

   | Old key | New key |
   |---|---|
   | `multiwovenConfig` | `platformConfig` |
   | `multiwovenServer.multiwovenServer` | `server.server` |
   | `multiwovenUI.multiwovenUI` | `ui.ui` |
   | `multiwovenWorker.multiwovenWorker` | `worker.worker` |
   | `multiwovenSolidWorker.multiwovenSolidWorker` | `solidWorker.solidWorker` |
   | `multiwovenPostgresql.multiwovenPostgresql` | `postgresql.postgresql` |
   | `hpa.multiwoven{Server,UI,Worker,SolidWorker}` | `hpa.{server,ui,worker,solidWorker}` |
   | `multipleDbHosts.multiwovenDB{Host,Name}` | `multipleDbHosts.platformDB{Host,Name}` |

3. **Pin any old defaults you relied on.** These defaults changed (0.118.0). Set the old value explicitly if your install
   used the default:

   ```yaml
   nameOverride: multiwoven
   kubernetesNamespace: multiwoven
   serviceAccount:
     name: multiwoven-service-account
   platformConfig:
     dbUsername: multiwoven
     dbName: multiwoven_server_production
     temporalPostgresUser: multiwoven
     temporalNamespace: multiwoven-dev
   ```

```
helm upgrade multiwoven aisquared/aisquared -f my-values.yaml
```

## Check detailed readme [here](https://docs.squared.ai/guides/setup/helm)


## Questions? Feedback?
[Join our slack](https://join.slack.com/t/multiwoven/shared_invite/zt-2bnjye26u-~lu_FFOMLpChOYxvovep7g)
