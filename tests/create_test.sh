TEST=$1

KUBECONFIG=$(ls -t1 ~/kube* | head -1)
export KUBECONFIG

kubectl create namespace $TEST
kubectl apply -f $TEST -n $TEST
