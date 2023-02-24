#!/bin/bash

set -x

## Env
DIR=$(pwd)
INSTALL="0"
CLUSTER_NAME=$1
REGION=$2
BASE_DOMAIN=$3
REPLICAS_CP=$4
REPLICAS_WORKER=$5
VPC=$6
AWS_ID=$7
AWS_SECRET_KEY=$8
OCP_VERSION=$9

## Prerequisites
echo "If you want to install a specific OCP version, type the version in format X.X"
echo "Downloading OCP 4 installer if not exists:"
if [ ! -z $OCP_VERSION ]; then
    if [ ! -f ./ocp4-installer.tar.gz ]; then
        echo "OCP VERSION: $OCP_VERSION"
        REMOTE_OCP_VERSION=$(curl -s https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.6/release.txt | grep Version: | awk '{print $2}')
        wget -O ./ocp4-installer.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest-4.6/openshift-install-linux-$REMOTE_OCP_VERSION.tar.gz && tar xvzf ./ocp4-installer.tar.gz
    else
        echo "Installer exists, using ./ocp4-installer.tar.gz. Unpacking..." ; echo " "
        tar xvzf ./ocp4-installer.tar.gz
    fi
else
    if [ ! -f ./ocp4-installer.tar.gz ]; then
        wget -O ./ocp4-installer.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux.tar.gz && tar xvzf ./ocp4-installer.tar.gz
    else
        echo "Installer exists, using ./ocp4-installer.tar.gz. Unpacking..." ; echo " "
        tar xvzf ./ocp4-installer.tar.gz
    fi
fi

if [ ! -f ./install/install-dir-$CLUSTER_NAME/terraform.cluster.tfstate ]; then
    echo "AWS credentials: "; echo " "
    aws configure set region $REGION --profile default 

cat << EOF > ~/.aws/credentials
[default]
aws_access_key_id = $AWS_ID
aws_secret_access_key = $AWS_SECRET_KEY
EOF

    cleanup() {
        rm -f ./openshift-install
        rm -f ./README.md
        rm -f ~/.ssh/myocp*
    }
    
    echo "Generating SSH key pair" ; echo " "
    rm -f ~/.ssh/myocp_$CLUSTER_NAME ; ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/myocp_$CLUSTER_NAME
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/myocp_$CLUSTER_NAME
    ssh-add -L
    
    ## Install config file
    echo "Creating install config file" ; echo " "
    rm -f ./install/install-dir-$CLUSTER_NAME/install-config.yaml && rm -f ./install/install-dir-$CLUSTER_NAME/.openshift_install* ; #./openshift-install create install-config --dir=install-dir-$CLUSTER_NAME
    
    mkdir ./backup/backup-$CLUSTER_NAME/
    mkdir ./install/install-dir-$CLUSTER_NAME/

    PULL_SECRET=`cat ./pullsecret.txt`
    SSH_KEY=`cat ~/.ssh/myocp_$CLUSTER_NAME.pub`
    
    if [ $VPC != false ]; then
      echo "Existing VPC is $VPC..."
      SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC  --query 'Subnets[?MapPublicIpOnLaunch==`false`].SubnetId' --output text)
      var=$'subnets:\n'

      for instance in $SUBNET_IDS; do envInstances+=(${instance}); done
      for i in ${envInstances[@]};
      do
	   var+="    "-" "\'$i\'$'\n'
      done

      EXISTING_VPC=$var
      echo "Existing subnets are $EXISTING_VPC"
    else
      EXISTING_VPC=""
      echo "No existing VPC..."
    fi	    

cat << EOF > ./backup/backup-$CLUSTER_NAME/install-config.yaml
additionalTrustBundlePolicy: Proxyonly
apiVersion: v1
baseDomain: $BASE_DOMAIN
compute:
- architecture: amd64
  hyperthreading: Enabled
  name: worker
  platform: {}
  replicas: $REPLICAS_WORKER
controlPlane:
  architecture: amd64
  hyperthreading: Enabled
  name: master
  platform: {}
  replicas: $REPLICAS_CP
metadata:
  creationTimestamp: null
  name: $CLUSTER_NAME
networking:
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  machineNetwork:
  - cidr: 10.0.0.0/16
  networkType: OVNKubernetes
  serviceNetwork:
  - 172.30.0.0/16
platform:
  aws:
    region: $REGION
    $EXISTING_VPC
pullSecret: '$PULL_SECRET'
sshKey: $SSH_KEY
EOF

    cp ./backup/backup-$CLUSTER_NAME/install-config.yaml ./install/install-dir-$CLUSTER_NAME/install-config.yaml
    cat ./install/install-dir-$CLUSTER_NAME/install-config.yaml

    echo "Edit the installation file ./install/install-dir-$CLUSTER_NAME/install-config.yaml if you need."
    echo "Confirm when you are ready:" ; echo " "
    
    while true; do
        read -p "Proceed with OCP cluster installation: yY|nN -> " yn
        case $yn in
                [Yy]* ) echo "Installing OCP4 cluster... " ; INSTALL="1" ; break;;
                [Nn]* ) echo "Aborting installation..." ; cleanup ; ssh-add -D ; exit;;
                * ) echo "Select yes or no";;
        esac
    done
    
    if [ $INSTALL -gt 0 ]; then
    ./openshift-install create cluster --dir=install/install-dir-$CLUSTER_NAME --log-level=info
    echo "Set HTPasswd as Identity Provider" ; echo " "
    ## PENDING: Modify oauth to apply different configuration to hub and snos
    ./oauth.sh $CLUSTER_NAME
    ssh-add -D
    fi
else
    echo "An OCP cluster exists. Skipping installation..."
    echo "Remove the install-dir folder and run the script."
fi

exit

