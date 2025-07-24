#!/bin/zsh

TEST=$1

if [[ -z $KUBECONFIG ]]; then
  echo "Set your KUBECONFIG"
  exit 1
fi

#KUBECONFIG=$(ls -t1 ~/kube* | head -1)
#export KUBECONFIG

NS=`basename $TEST`
kubectl create namespace $NS
kubectl apply -f $TEST -n $NS
