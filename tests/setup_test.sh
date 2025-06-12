#!/bin/bash
TEST=$1

source $TEST/bliss_setup.env

if [ ! $TEST ]; then
  echo "Supply one argument for test folder"
  exit 1
fi

if [ ! -d $TEST ]; then
  echo "Test directory $TEST missing"
  exit 1
fi

#~/scripts/bliss_prov_435.sh

bliss provision aws-k3s \
--template=aws_k3_small \
--subnet-id $myPublicSubnet \
--region $myRegion \
--security-groups $mySG  \
--key-pair-name $myKeyPair \
--cluster-name $myCluster \
--ami-id $myAMI \
--tag Owner=$OWNER \
--tag TTL=1d \
--iam-profile-arn arn:aws:iam::034362041757:instance-profile/bliss-k3s-instance-profile \
--reinstall

#~/scripts/bliss_install_435.sh

bliss install \
--quay-username=$QUAY_USERNAME \
--quay-password=$QUAY_PASSWORD \
--weka-image $WEKA_IMAGE \
--cluster-name $myCluster \
--operator-version $OPERATOR_VERSION \
--no-csi \
--no-csi-sc \
--no-weka-cluster \
--no-operator

KUBECONFIG=$(ls -t1 ~/kube* | head -1)
export KUBECONFIG

cp $KUBECONFIG ..

echo $KUBECONFIG

helm upgrade --create-namespace \
  --install weka-operator oci://quay.io/weka.io/helm/weka-operator \
  --namespace weka-operator-system \
  --version $OPERATOR_VERSION \
  --set imagePullSecret=quay-io-robot-secret

helm repo add csi-wekafs https://weka.github.io/csi-wekafs
helm install csi-wekafs csi-wekafs/csi-wekafsplugin \
  --namespace csi-wekafs --create-namespace \
  --version $CSI_VERSION \
  --set pluginConfig.allowInsecureHttps=true


