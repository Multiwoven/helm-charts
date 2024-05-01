echo "installing cert-manager and cert-manager CRDs"
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.14.5 --set installCRDs=true

cd charts/multiwoven

apiHost="api.squared.ai"
uiHost="app.squared.ai"
uiImage="angeloaisquared/xtqsnrkm3hkyxsx8mtkgacah"

echo "install multiwoven"
helm upgrade -i multiwoven . \
    --set multiwovenConfig.apiHost=$apiHost \
    --set multiwovenConfig.uiHost=$uiHost \
    --set multiwovenConfig.viteApiHost=$apiHost \
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
    --set temporalUi.temporalUi.env.temporalCorsOrigins=https://$apiHost

echo "installing ingress-nginx resources"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

echo "installation complete"


cat << EOF
Final Steps
(1) go into the Azure portal, navigate to your cluster. Go to Services and Ingresses 
and click on the Ingresses tab. Wait for the IP address to appear.

(2) go into your DNS record set and add A records for app.squared.ai and api.squared.ai, 
using that IP address for both. Certificates will not be issued by the issuer until
you update your DNS records. The challenge needs to be able to use your subdomain to
reach your K8s cluster.
EOF



# checks

# check certificates
# kubectl describe -n multiwoven certificate ui-tls-cert
# 