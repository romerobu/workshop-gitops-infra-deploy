# workshop-gitops-infra-deploy

## Create cluster

:warning: First of all, create a **./pullsecret.txt** containing the pull secret to be used.

This script deploy OCP both hub and SNO managed on AWS. You must specify the following params:

```bash
sh ocp4-install.sh <cluster_name> <region_aws> <base_domain> <replicas_master> <replicas_worker> <vpc_id|false> <aws_id> <aws_secret> <ocp_version|null>
```
VPC id is required only if you are deploying on an existing VPC, otherwise specify "false". 
OCP version is not a required input value either, you can skip it if you want to install the latest version.

```bash
sh ocp4-install.sh argo-hub eu-central-1 <base_domain> 3 3 false <aws_id> <aws_secret> 
```
For deploying a SNO managed cluster:

```bash
sh ocp4-install.sh sno-1 eu-central-1 <base_domain> 1 0 <vpc_id> <aws_id> <aws_secret> 
```
:warning: It is recommended to name hub and sno clusters as *argo-hub* and *sno-x*

You can check your VPC id on AWS console or by running this command:

```bash
aws ec2 describe-vpcs 
```

## Deploy and configure ArgoCD

:warning: You need to install argocd [CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/).

This script installs GitOps operator, deploy ArgoCD instance and add managed clusters. You must specify the amount of deployed SNO clusters to be managed by argocd:

```bash
sh deploy-gitops.sh <amount_of_sno_clusters>
```

For example, if you want to add 3 sno cluster (sno-1, sno-2 and sno-3):

```bash
sh deploy-gitops.sh 3
```

## Destroy cluster

If you want to delete a cluster, first run this command to destroy it from AWS:

```bash
CLUSTER_NAME=<cluster_name>
openshift-install destroy cluster --dir install/install-dir-$CLUSTER_NAME --log-level info
```
Then remove it from ArgoCD instance:

```bash
# Make sure you are logged in cluster hub, unless you are trying to delete this cluster that this section is not required
export KUBECONFIG=./install/install-dir-argo-hub/auth/kubeconfig
# Login to argo server
ARGO_SERVER=$(oc get route -n openshift-operators argocd-server  -o jsonpath='{.spec.host}')
ADMIN_PASSWORD=$(oc get secret argocd-cluster -n openshift-operators  -o jsonpath='{.data.admin\.password}' | base64 -d)
# Remove managed cluster
argocd login $ARGO_SERVER --username admin --password $ADMIN_PASSWORD --insecure
argocd cluster rm $CLUSTER_NAME
# Then remove installation directories
rm -rf ./backup/backup-$CLUSTER_NAME
rm -rf ./install/install-dir-$CLUSTER_NAME
```
