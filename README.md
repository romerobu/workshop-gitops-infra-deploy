# workshop-gitops-infra-deploy

## Create cluster

This script deploy OCP both hub and SNO managed on AWS. You must specify the following params:

VPC id is required only if you are deploying on an existing VPC, otherwise pass "false". OCP version is not a required input value either, you can skip it if you want to install the latest version.

```bash
sh ocp4-install.sh <cluster_name> <region_aws> <base_domain> <replicas_master> <replicas_worker> <vpc_id|false> <aws_id> <aws_secret> <ocp_version|null>
```
For example, if you want to deploy a argo-hub cluster:

```bash
sh ocp4-install.sh argo-hub eu-west-1 xxx 3 1 false <aws_id> <aws_secret> 
```
For deploying a sno managed cluster:

```bash
sh ocp4-install.sh sno-1 eu-west-1 xxx 1 0 xxxx <aws_id> <aws_secret> 
```
## Deploy and configure ArgoCD

This script installs GitOps operator, deploy ArgoCD instance and add managed clusters. You must specify the amount of clusters to be managed by argocd:

```bash
sh deploy-gitops.sh <amount_clusters>
```

## Destroy cluster

If you want to delete a cluster, first run this command to destroy it from AWS:

```bash
openshift-install destroy cluster --dir install/install-dir-<cluster_name> --log-level info
```

Then remove it from ArgoCD instance:

```bash
ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)

argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
argocd cluster rm <cluster_name>
```
