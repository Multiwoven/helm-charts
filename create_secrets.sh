kubectl delete secret temporal-cloud -n multiwoven

kubectl create secret generic temporal-cloud -n multiwoven \
    --from-file=temporal-root-cert=./temporal.pem \
    --from-file=temporal-client-key=./temporal.key