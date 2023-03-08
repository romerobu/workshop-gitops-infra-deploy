#!/bin/bash

CLUSTER=$1

export KUBECONFIG=./install/install-dir-argo-hub/auth/kubeconfig

echo "Login to argo hub cluster"

oc apply -f gitops-operator/subscription.yaml

#while [[ $(oc get pods -n openshift-operators -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
#   sleep 1
#done
echo "Operator installed..."

oc apply -f gitops-operator/argo-instance.yaml

rm -r ./gitops-operator/argo-rbac.csv
touch ./gitops-operator/argo-rbac.csv
echo -e "g, system:cluster-admins, role:admin \n" >> ./gitops-operator/argo-rbac.csv

sleep 7
echo "ArgoCD instance installed..."

ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)

argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
echo "Login to argocd servr..."

for i in $(seq 2 $CLUSTER);do

   
   export KUBECONFIG=./install/install-dir-sno-$i/auth/kubeconfig
   CONTEXT=$(kubectl config get-contexts -o name)
   argocd proj create project-sno-$i
   argocd cluster add $CONTEXT --kubeconfig ./install/install-dir-sno-$i/auth/kubeconfig --name sno-$i --project project-sno-$i
   echo "Added cluster sno-$i"
   
   # Configure argo project and restrictions
   argocd proj add-destination project-sno-$i https://api.sno-$i.*.opentlc.com:6443 '*'
   argocd proj add-source project-sno-$i '*'
   
   # Configure RBAC project roles
   argocd proj role create project-sno-$i admin-sno-$i
   argocd proj role add-group project-sno-$i admin-sno-$i admin-sno-$i
   argocd proj allow-cluster-resource project-sno-$i '*' '*'
   
   echo -e "p, role:admin-sno-$i, applications, *, project-sno-$i/*, allow \n" >> ./gitops-operator/argo-rbac.csv
   echo -e "p, role:admin-sno-$i, clusters, get, project-sno-$i/*, allow \n" >> ./gitops-operator/argo-rbac.csv
   echo -e "g, admin-sno-$i, role:admin-sno-$i \n" >> ./gitops-operator/argo-rbac.csv
   
   # Create groups
   export KUBECONFIG=./install/install-dir-argo-hub/auth/kubeconfig
   oc adm groups new admin-sno-$i
   oc adm groups add-users admin-sno-$i user-$i 

done

# Update argo rbac
export POLICY=$(cat gitops-operator/argo-rbac.csv)
yq e -i '.spec.rbac.policy = env(POLICY)' gitops-operator/argo-instance.yaml
oc apply -f ./gitops-operator/argo-instance.yaml

argocd cluster list
echo "Done adding clusters"

# Deploy keycloak

oc new-project keycloak
oc process -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/openshift-examples/keycloak.yaml \
    -p KEYCLOAK_ADMIN=admin \
    -p KEYCLOAK_ADMIN_PASSWORD=admin \
    -p NAMESPACE=keycloak \
| oc create -f -

KEYCLOAK_URL=https://$(oc get route keycloak --template='{{ .spec.host }}') &&
echo "" &&
echo "Keycloak:                 $KEYCLOAK_URL" &&
echo "Keycloak Admin Console:   $KEYCLOAK_URL/admin" &&
echo "Keycloak Account Console: $KEYCLOAK_URL/realms/myrealm/account" &&
echo ""

oc -n openshift-ingress-operator get secret router-ca -o jsonpath="{ .data.tls\.crt }" | base64 -d -i > ca.crt
oc -n openshift-config create cm keycloak-ca --from-file=ca.crt

# Create realm, user, client, credentials (token) and create secret
