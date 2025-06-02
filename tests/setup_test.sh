#!/bin/bash
TEST=$1
OPERATOR_VERSION=v1.4.0

if [ ! $TEST ]; then
  echo "Supply one argument for test folder"
  exit 1
fi

if [ ! -d $TEST ]; then
  echo "Test directory $TEST missing"
  exit 1
fi

~/scripts/bliss_prov_435.sh
~/scripts/bliss_install_435.sh

KUBECONFIG=$(ls -t1 ~/kube* | head -1)
export KUBECONFIG

cp $KUBECONFIG ..

echo $KUBECONFIG

helm upgrade --create-namespace \
  --install weka-operator oci://quay.io/weka.io/helm/weka-operator \
  --namespace weka-operator-system \
  --version $OPERATOR_VERSION \
  --set imagePullSecret=quay-io-robot-secret


kubectl apply -f $TEST
