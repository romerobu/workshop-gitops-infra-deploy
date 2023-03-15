#!/bin/bash

CLUSTER=$1
DOMAIN=$2

export KUBECONFIG=./install/install-dir-argo-hub/auth/kubeconfig
echo "Login to argo hub cluster"

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

for i in $(seq 1 $CLUSTER);do

   # Configure keycloak realm, client and users
   pod=$(oc get pods -o custom-columns=POD:.metadata.name --no-headers -n keycloak --field-selector=status.phase=Running)
 
   oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh create realms -s realm=myrealm-$i -s enabled=true --no-config --server http://localhost:8080 --realm master --user admin --password admin"
   oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh create clients -r myrealm-$i -s clientId=myclient-$i -s enabled=true --no-config --server http://localhost:8080 --realm master --user admin --password admin" 
   id=$(oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh get clients -q clientId=myclient-$i -r myrealm-$i --fields id --format csv --noquotes --no-config --server http://localhost:8080 --realm master --user admin --password admin" | sed -n '2p')

   oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh update clients/${id:0:$(expr length $id)-1} -s 'redirectUris=[\"https://oauth-openshift.apps.sno-$i.$DOMAIN/oauth2callback/keycloak/*\"]' -s 'directAccessGrantsEnabled=true' -r myrealm-$i --no-config --server http://localhost:8080 --realm master --user admin --password admin"
   #oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh update clients/${id:0:$(expr length $id)-1} -s 'redirectUris=[\"https://*\"]' -s 'directAccessGrantsEnabled=true' -r myrealm-$i --no-config --server http://localhost:8080 --realm master --user admin --password admin"
   oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh create users -s username=myuser-$i -s enabled=true -r myrealm-$i --no-config --server http://localhost:8080 --realm master --user admin --password admin"
   oc exec -it $pod -- sh -c "/opt/keycloak/bin/kcadm.sh set-password --username myuser-$i --new-password myuser-$i -r myrealm-$i --temporary --no-config --server http://localhost:8080 --realm master --user admin --password admin"

done



