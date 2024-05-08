#!/bin/bash

echo "Upgrading Multiwoven in Staging"

apiHost="api-staging.squared.ai"
temporalHost="temporal-staging.squared.ai"
viteApiHost='https://api-staging.squared.ai' #unfortunately, due to the required single quotes, you havce to add the userPrefix manually. Don't forget!!
uiHost="app-staging.squared.ai"
uiImage="angeloaisquared/xtqsnrkm3hkyxsx8mtkgacah"

cd charts/multiwoven
helm upgrade -i multiwoven . \
    --set multiwovenConfig.apiHost=$apiHost \
    --set multiwovenConfig.uiHost=$uiHost \
    --set multiwovenConfig.viteApiHost=$viteApiHost \
    --set multiwovenConfig.tlsCertIssuer="letsencrypt-prod" \
    --set multiwovenServer.ports[0].name="80-3000" \
    --set multiwovenServer.ports[0].port=80 \
    --set multiwovenServer.ports[0].targetPort=3000 \
    --set multiwovenServer.ports[1].name="443-3000" \
    --set multiwovenServer.ports[1].port=443 \
    --set multiwovenServer.ports[1].targetPort=3000 \
    --set multiwovenUI.multiwovenUI.image.repository=$uiImage \
    --set multiwovenUI.ports[0].name="80-8000" \
    --set multiwovenUI.ports[0].port=80 \
    --set multiwovenUI.ports[0].targetPort=8000 \
    --set multiwovenUI.ports[1].name="443-8000" \
    --set multiwovenUI.ports[1].port=443 \
    --set multiwovenUI.ports[1].targetPort=8000 \
    --set temporalUi.temporalUi.env.temporalCorsOrigins=https://$apiHost \
    --set multiwovenConfig.temporalUiHost=temporal-staging.squared.ai \
    --set temporal.enabled=false \
    --set multiwovenConfig.temporalHost=production.pirhu.tmprl.cloud \
    --set multiwovenConfig.temporalNamespace=production.pirhu \
    --set multiwovenWorker.multiwovenWorker.args={./app/temporal/cli/worker}