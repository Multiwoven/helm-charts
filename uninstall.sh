cd charts/multiwoven
echo "uninstalling multiwoven"
helm uninstall multiwoven

echo "deleting nginx-ingress resources. This can take a few minutes."
kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml

echo "uninstalling cert-manager"
helm uninstall cert-manager -n cert-manager
