#!/bin/bash

if [[ -z $KUBECONFIG ]]; then
  echo "Set your KUBECONFIG"
  exit 1
fi

while true; do
    echo "KUBECONFIG=$KUBECONFIG"
    read -p "Do you want to proceed? (y/n): " yn
    case $yn in
        [Yy]* ) echo "Proceeding..."; break;; # Executes if user enters 'y' or 'Y'
        [Nn]* ) echo "Exiting..."; exit;;    # Exits if user enters 'n' or 'N'
        * ) echo "Invalid response. Please answer 'y' or 'n'.";; # Handles invalid input
    esac
done

myCluster=ranzo-20250717-1
myCluster=$(basename $KUBECONFIG | awk -F"." '{print $1}'| sed 's/kube-//')

echo $myCluster

#KUBECONFIG=$(ls -t1 ~/kube* | head -1)
#KUBECONFIG=~/kube-$myCluster.yaml
#export KUBECONFIG

export AWS_PROFILE=ranzo

aws sso login

source ./bliss_setup.env

#if [ ! $TEST ]; then
#  echo "Supply one argument for test folder"
#  exit 1
#fi
#
#if [ ! -d $TEST ]; then
#  echo "Test directory $TEST missing"
#  exit 1
#fi

#Workaround bliss provision reinstall doesn't handle csi test waiting on mounts
kubectl delete ds csi-wekafs-test-api -n default --wait=false --ignore-not-found=true --request-timeout=3s
while [ $(kubectl get ds csi-wekafs-test-api -n default --no-headers --ignore-not-found=true --request-timeout=3s | wc | awk '{print $1}') -gt 0 ]; do
 echo "Waiting for DaemonSet csi-wekafs-test-api to be deleted..."
 sleep 1
done


#Workaround bliss provision reinstall doesn't handle the case of a WekaCluster running.
kubectl delete WekaCluster cluster-dev -n default --wait=false --ignore-not-found=true --request-timeout=3s
kubectl patch WekaCluster cluster-dev -n default --type='merge' -p='{"spec":{"gracefulDestroyDuration": "0s"}}' --request-timeout=3s

while [ $(kubectl get wekacluster --all-namespaces --no-headers --ignore-not-found=true --request-timeout=3s | wc | awk '{print $1}') -gt 0 ]; do
 echo "Waiting for WekaClusters to be deleted..."
 sleep 1
done

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


