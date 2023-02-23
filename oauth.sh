#!/bin/bash

CURRENT_DIR=$(pwd)

CLUSTER_NAME=$1

echo "Exporting admin TLS credentials..."
export KUBECONFIG=$CURRENT_DIR/install/install-dir-$CLUSTER_NAME/auth/kubeconfig

echo "Creating htpasswd file"
rm -f ./oauth/htpasswd
htpasswd -c -b -B ./oauth/htpasswd admin redhat
htpasswd -b -B ./oauth/htpasswd andrew r3dh4t1!
htpasswd -b -B ./oauth/htpasswd karla r3dh4t1!
htpasswd -b -B ./oauth/htpasswd marina r3dh4t1!


echo "Creating HTPasswd Secret"
oc create secret generic htpass-secret --from-file=htpasswd=./oauth/htpasswd -n openshift-config --dry-run -o yaml | oc apply -f -

echo "Configuring HTPassw identity provider"
cat > ./oauth/cluster-oauth.yaml << EOF_IP
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
oc apply -f ./oauth/cluster-oauth.yaml

echo "Giving cluster-admin role to admin user"
oc adm policy add-cluster-role-to-user cluster-admin admin

echo "Remove kubeadmin user"
oc delete secrets kubeadmin -n kube-system --ignore-not-found=true
