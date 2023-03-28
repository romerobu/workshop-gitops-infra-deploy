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

:warning: You need to install argocd [CLI](https://argo-cd.readthedocs.io/en/stable/cli_installation/) and [yq](https://www.cyberithub.com/how-to-install-yq-command-line-tool-on-linux-in-5-easy-steps/).

This script installs GitOps operator, deploy ArgoCD instance and add managed clusters. You must specify the amount of deployed SNO clusters to be managed by argocd:

```bash
sh deploy-gitops.sh <amount_of_sno_clusters>
```

For example, if you want to add 3 sno cluster (sno-1, sno-2 and sno-3):

```bash
sh deploy-gitops.sh 3
```

This script configures argo RBAC so users created in hub cluster for sno managed cluster (user-1, user-2...) can only view project-sno-x and destination sno-x clusters hence only deploying to the allowed destination within the allowed project.

## Deploy keycloak

To deploy an instance of keycloak and create the corresponding realms, client and users, run this script:

```bash
sh set-up-keycloak.sh <number_of_clusters> <subdomain>
```

## Deploy FreeIPA

Follow the instructions [here](https://github.com/redhat-cop/helm-charts/tree/master/charts/ipa) to deploy FreeIPA server.

### Create FreeIPA users

To create FreeIPA users, run these commands:

```bash
# Login to kerberos
oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd123 | /usr/bin/kinit admin"
    
# Create groups if they dont exist

oc exec -it dc/ipa -n ipa -- \
    sh -c "ipa group-add student --desc 'wrapper group' || true && \
    ipa group-add ocp_admins --desc 'admin openshift group' || true && \
    ipa group-add ocp_devs --desc 'edit openshift group' || true && \
    ipa group-add ocp_viewers --desc 'view openshift group' || true && \
    ipa group-add-member student --groups=ocp_admins --groups=ocp_devs --groups=ocp_viewers || true"

# Add demo users

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add paul --first=paul \
    --last=ipa --email=paulipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_admins --users=paul"

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add henry --first=henry \
    --last=ipa --email=henryipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_devs --users=henry"

oc exec -it dc/ipa -n ipa -- \
    sh -c "echo Passw0rd | \
    ipa user-add mark --first=mark \
    --last=ipa --email=markipa@redhatlabs.dev --password || true && \
    ipa group-add-member ocp_viewers --users=mark"
```

## Deploy vault server

To deploy an instance of vault server:

```bash
oc login -u kubeadmin -p xxxxx https://api.my.domain.com:6443

helm repo add hashicorp https://helm.releases.hashicorp.com

oc new-project vault

helm install vault hashicorp/vault \
    --set "global.openshift=true" \
    --set "server.dev.enabled=true" --values values.openshift.yaml

oc exec -it vault-0 -- /bin/sh

  vault auth enable kubernetes

  vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"

  exit
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
