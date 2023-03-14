#!/bin/bash

CURRENT_DIR=$(pwd)

CLUSTER_NAME=$1
ADMIN=$2

echo "Exporting admin TLS credentials..."
export KUBECONFIG=$CURRENT_DIR/install/install-dir-$CLUSTER_NAME/auth/kubeconfig

echo "Creating htpasswd file"

rm -f ./oauth/oauth-$CLUSTER_NAME/htpasswd
mkdir -p oauth
mkdir -p oauth/oauth-$CLUSTER_NAME

echo "--------------------------> $ADMIN"

if [ $ADMIN == false ]; then

  echo "Creating users for cluster hub..."
  htpasswd -c -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd admin redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-1 redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-2 redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-3 redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-4 redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-5 redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd user-6 redhat

else

  echo "Creating users for SNO cluster"
  htpasswd -c -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd admin redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd peter redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd karla redhat
  htpasswd -b -B ./oauth/oauth-$CLUSTER_NAME/htpasswd anna redhat

fi



echo "Creating HTPasswd Secret"
oc create secret generic htpass-secret --from-file=htpasswd=./oauth/oauth-$CLUSTER_NAME/htpasswd -n openshift-config --dry-run -o yaml | oc apply -f -

echo "Configuring HTPassw identity provider"
cat > ./oauth/oauth-$CLUSTER_NAME/cluster-oauth.yaml << EOF_IP
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider 
    mappingMethod: claim 
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret
EOF_IP
oc apply -f ./oauth/oauth-$CLUSTER_NAME/cluster-oauth.yaml

echo "Giving cluster-admin role to admin user"
oc adm policy add-cluster-role-to-user cluster-admin admin

echo "Remove kubeadmin user"
oc delete secrets kubeadmin -n kube-system --ignore-not-found=true
