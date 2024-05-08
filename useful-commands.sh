# To restart a deployment

kubectl rollout restart deployment/multiwoven-temporal -n multiwoven
kubectl rollout restart deployment/multiwoven-temporal-ui -n multiwoven
kubectl rollout restart deployment/multiwoven-ui -n multiwoven


kubectl rollout restart deployment/multiwoven-worker -n multiwoven
kubectl rollout restart deployment/multiwoven-server -n multiwoven

kubectl rollout restart deployment/multiwoven-temporal -n multiwoven


helm rollback multiwoven 15 # DO NOT include the -n multiwoven. The release metadata is stored in the default namespace.

# verify context
kubectl config get-contexts