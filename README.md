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

## Custom-domain local checks

Run these checks from this repository without a Kubernetes cluster:

```sh
helm lint charts/aisquared
ruby tests/custom_domains_test.rb
python3 tests/caddy_routing_test.py
```

The render tests require Helm and Ruby 3.1 or later. They check disabled defaults,
plaintext and SecretProviderClass credential wiring, service port remapping,
ExternalDNS annotations, the retained certificate volume, AWS NLB controller
selection, and invalid feature configurations. The routing tests also require
Caddy, Python 3, and Ruby's standard YAML library; they use temporary loopback
servers and a private CA without installing certificates in system trust or
contacting public certificate authorities.

Caddy's NLB Service explicitly selects AWS Load Balancer Controller using
`service.beta.kubernetes.io/aws-load-balancer-type: external` and IP targets.
See the [controller's Service annotation contract](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/service/annotations/#traffic-routing).
If a Service has already been provisioned with another controller, plan its
migration separately; these local checks do not modify any existing Service.

Enable `customDomains.enabled` and `caddy.enabled` together and supply the
custom-domains database host, API key, webhook secret, and Caddy origin hostname
and customer CNAME target. The custom-domains database must be separate from
Rails because their migration tables use different formats. Configure the origin
suffix to match the published-app ingress and Rails `APPGEN_PUBLISHED_DOMAIN`.
Public DNS, AWS provisioning, origin certificates, and public ACME issuance still
require validation in the target environment.
