#!/bin/zsh

# Note the privs in this example may be too high, this is the admin login
CLUSTER_SECRET_NAME=weka-cluster-cluster-dev

#Assumes one WekaCluster
NAMESPACE=$(kubectl get pod $COMPUTE_POD --no-headers=true -o custom-columns=NAME:.metadata.namespace | tail -1)
COMPUTE_POD=$(kubectl get pod --selector=app=weka,weka.io/mode=compute -n $NAMESPACE  -o custom-columns=NAME:.metadata.name --no-headers=true | tail -1)
#NAMESPACE=$(kubectl get pod $COMPUTE_POD --no-headers=true --all-namespaces  -o custom-columns=NAME:.metadata.namespace)
#NAMESPACE=$(kubectl get pod $COMPUTE_POD --no-headers=true -o custom-columns=NAME:.metadata.namespace)

SECRET=weka-client-cluster-dev

#Breaks if token not the last line
JOINTOKEN=$(kubectl exec $COMPUTE_POD -n $NAMESPACE -- weka cluster join-token generate --access-token-timeout 52w | tail -1)
ENCODED_JOINTOKEN=$(echo -n $JOINTOKEN | base64) 

USERNAME=$(kubectl get secret $CLUSTER_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.username}' | base64 -d)
PASSWORD=$(kubectl get secret $CLUSTER_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.password}' | base64 -d)
ORG=$(kubectl get secret $CLUSTER_SECRET_NAME -n $NAMESPACE -o jsonpath='{.data.org}' | base64 -d)
#echo $USERNAME
 
kubectl create secret generic weka-client-cluster-dev  \
  --namespace $NAMESPACE \
  --from-literal=username=$USERNAME \
  --from-literal=password=$PASSWORD \
  --from-literal=org=$ORG
