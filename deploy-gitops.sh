#!/bin/bash

CLUSTER=$1

oc apply -f gitops-operator/subscription.yaml

#while [[ $(oc get pods -n openshift-operators -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
#   sleep 1
#done
echo "Operator installed..."

oc apply -f gitops-operator/argo-instance.yaml
echo "ArgoCD instance installed..."

ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)

argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
echo "Login to argocd servr..."

for i in $(seq 1 $CLUSTER);do
   export KUBECONFIG=install-dir-sno-$i/auth/kubeconfig
   CONTEXT=$(kubectl config get-contexts -o name)
   argocd cluster add $CONTEXT --kubeconfig install-dir-sno-$i/auth/kubeconfig --name sno-$i
   echo "Added cluster sno-$i"
done

argocd cluster list

echo "Done adding clusters"
