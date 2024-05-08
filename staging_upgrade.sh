
    git checkout temporal-ui
    
    # az login
    # az account set --subscription 52c30c8f-6107-408c-aea2-0053500b4531
    # az aks get-credentials --resource-group AngeloDevTest --name AngeloAKSCluster --overwrite-existing
    
    echo "Upgrading Multiwoven in Staging"

    # apiHost="api-staging.squared.ai"
    # viteApiHost='https://api-staging.squared.ai' #unfortunately, due to the required single quotes, you havce to add the userPrefix manually. Don't forget!!
    # uiHost="app-staging.squared.ai"
    # uiImage="angeloaisquared/xtqsnrkm3hkyxsx8mtkgacah"

    # sh staging.sh
    # cd charts/multiwoven
    # helm upgrade -i multiwoven .     #     --set multiwovenConfig.apiHost=$apiHost     #     --set multiwovenConfig.uiHost=$uiHost     #     --set multiwovenConfig.viteApiHost=$viteApiHost     #     --set multiwovenConfig.tlsCertIssuer="letsencrypt-prod"     #     --set multiwovenServer.ports[0].name="80-3000"     #     --set multiwovenServer.ports[0].port=80     #     --set multiwovenServer.ports[0].targetPort=3000     #     --set multiwovenServer.ports[1].name="443-3000"     #     --set multiwovenServer.ports[1].port=443     #     --set multiwovenServer.ports[1].targetPort=3000     #     --set multiwovenUI.multiwovenUI.image.repository=$uiImage     #     --set multiwovenUI.ports[0].name="80-8000"     #     --set multiwovenUI.ports[0].port=80     #     --set multiwovenUI.ports[0].targetPort=8000     #     --set multiwovenUI.ports[1].name="443-8000"     #     --set multiwovenUI.ports[1].port=443     #     --set multiwovenUI.ports[1].targetPort=8000     #     --set temporalUi.temporalUi.env.temporalCorsOrigins=https://$apiHost     #     --set multiwovenConfig.temporalUiHost=temporal-staging.squared.ai
    