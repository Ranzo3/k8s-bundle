kubectl create secret generic weka-client-cluster-dev  \
  --namespace default \
  --from-literal=username=admin \
  --from-literal=password=Admin123 \
  --from-literal=org=Root
