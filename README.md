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
helm install multiwoven aisquared/aisquared -f my-values.yaml
```

Keep the release name `multiwoven`: the chart's default in-cluster addresses (`dbHost`, `temporalHost`,
`lightningUrl`) assume the resource names that release name produces.

## Check detailed readme [here](https://docs.squared.ai/guides/setup/helm)


## Questions? Feedback?
[Join our slack](https://join.slack.com/t/multiwoven/shared_invite/zt-2bnjye26u-~lu_FFOMLpChOYxvovep7g)
