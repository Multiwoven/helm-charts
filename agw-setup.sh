# helm repo add aad-pod-identity https://raw.githubusercontent.com/Azure/aad-pod-identity/master/charts
# helm install aad-pod-identity aad-pod-identity/aad-pod-identity

# az login

# helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
# helm repo update

export APPGW_NAME=mwclusterappgateway
export RESOURCE_GROUP=MultiwovenHelm
export AKS_NAME=MultiwovenCluster
export AKS_RESOURCE_GROUP=MultiwovenHelm
export IDENTITY_RESOURCE_GROUP=MultiwovenHelm
export IDENTITY_CLIENT_ID=ARMDeploymentID

helm install ingress-azure application-gateway-kubernetes-ingress/ingress-azure \
  --set appgw.name=$APPGW_NAME \
  --set appgw.resourceGroup=$RESOURCE_GROUP \
  --set appgw.subscriptionId=$(az account show --query id -o tsv) \
  --set appgw.shared=false \
  --set armAuth.type=aadPodIdentity \
  --set armAuth.identityResourceID=$(az identity show --name $IDENTITY_CLIENT_ID --resource-group $IDENTITY_RESOURCE_GROUP --query id -o tsv) \
  --set armAuth.identityClientID=$IDENTITY_CLIENT_ID \
  --set kubernetes.watchNamespace=multiwoven \
  --set rbac.enabled=true \
  --set verbosityLevel=3


# az network application-gateway show --name $APPGW_NAME --resource-group $RESOURCE_GROUP --output table

# helm uninstall ingress-azure
