#/bin/bash
if [ "$(aws sts get-caller-identity --no-cli-pager 2>&1 > /dev/null ; echo $?)" -ne 0 ]; then
  echo "Wrong AWS credentials. Aborting..."
  exit 99
fi

if [ "$(aws ec2 describe-vpcs --no-cli-pager | jq -r '.Vpcs' | jq length)" -ne 1 ];then
  echo "VPC does not exist." ; echo " "
  exit 99
fi

VPC_ID=$(aws ec2 describe-vpcs --no-cli-pager | jq -r '.Vpcs[].VpcId')

SUBNETS=$(aws ec2 describe-subnets --output json | jq -r ".Subnets[]")
while read -r i
do
  if [[ "$(echo $i | jq -r '.Tags[].Value')" == *"public"*"1a"* ]]; then
    PUBLIC_SUBNET=$(echo $i | jq -r '.SubnetId')
  fi
   if [[ "$(echo $i | jq -r '.Tags[].Value')" == *"mysql-nmstate"* ]]; then
    MYSQL_SUBNET=$(echo $i | jq -r '.SubnetId')
  fi
done < <(echo $SUBNETS | jq -c)

echo "Creating key-pair:"
aws ec2 create-key-pair \
   --key-name  mysql-nmstate \
   --query 'KeyMaterial' --output text > ~/.ssh/mysql-nmstate
if [ "$(stat -L -c "%a" ~/.ssh/mysql-nmstate)" != "400" ];then
  chmod 400 ~/.ssh/mysql-nmstate
fi
echo "Done" ; echo " "

echo "########### Deploying bastion instance ###########" ; echo " "
echo "Creating bastion SG:"
aws ec2 create-security-group --no-cli-pager \
    --group-name bastion-sg \
    --description "bastion SG" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=bastion-sg}]' \
    --vpc-id "$VPC_ID"
echo "Done" ; echo " "

SGS=$(aws ec2 describe-security-groups --output json | jq -r ".SecurityGroups[]")
while read -r i
do
  if [[ "$(echo $i | jq -r '.GroupName')" == *"bastion-sg"* ]]; then
    BASTION_SG_ID=$(echo $i | jq -r '.GroupId')
  fi
done < <(echo $SGS | jq -c)

echo "Allow SSH from your IP:" ; echo " "
IP=$(curl -s https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress --no-cli-pager \
    --group-id $BASTION_SG_ID \
    --protocol tcp \
    --port 22 \
    --cidr "$IP/32"
echo "Done" ; echo " "

echo "Starting bastion instance:" ; echo " "
aws ec2 run-instances --no-cli-pager \
    --image-id ami-0ec7f9846da6b0f61 \
    --count 1 \
    --instance-type t2.micro \
    --key-name mysql-nmstate \
    --security-group-ids $BASTION_SG_ID \
    --subnet-id $PUBLIC_SUBNET \
    --associate-public-ip-address \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bastion}]' 'ResourceType=volume,Tags=[{Key=Name,Value=bastion-disk}]' \
    2>&1 > /dev/null

echo "Done" ; echo " "

echo "Waiting 60s for instance to startup..."
sleep 60

INSTANCES=$(aws ec2 describe-instances --output json | jq -r ".Reservations[] | .Instances[] ")
while read -r i
do
  if [[ "$(echo $i | jq -r '.Tags[].Value')" == *"bastion"* ]] && [[ "$(echo $i | jq -r '.State.Name')" == "running" ]]; then
    BASTION_ID=$(echo $i | jq -r '.InstanceId')
  fi
done < <(echo $INSTANCES | jq -c)

BASTION_PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $BASTION_ID --no-cli-pager | jq -r '.Reservations[].Instances[].PublicIpAddress' | head -1)

echo "########### Deploying mysql instance ###########" ; echo " "

echo "Creating Mysql-nmstate SG:" ; echo " "
aws ec2 create-security-group --no-cli-pager \
    --group-name mysql-nmstate-sg \
    --description "Mysql-nmstate SG" \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=mysql-nmstate-sg}]' \
    --vpc-id "$VPC_ID"
echo "Done" ; echo " "

SGS=$(aws ec2 describe-security-groups --output json | jq -r ".SecurityGroups[]")
while read -r i
do
  if [[ "$(echo $i | jq -r '.GroupName')" == *"mysql-nmstate-sg"* ]]; then
  MYSQL_SG_ID=$(echo $i | jq -r '.GroupId')
  fi
done < <(echo $SGS | jq -c)

echo "Allow all traffic intra-subnets:"
aws ec2 authorize-security-group-ingress --no-cli-pager \
    --group-id "$MYSQL_SG_ID" \
    --protocol all \
    --cidr "10.0.0.0/16"
echo "Done" ; echo " "

echo "Starting mysql instance:" ; echo " "
aws ec2 run-instances --no-cli-pager \
    --image-id ami-0ec7f9846da6b0f61 \
    --count 1 \
    --instance-type t2.micro \
    --key-name mysql-nmstate \
    --security-group-ids $MYSQL_SG_ID \
    --subnet-id $MYSQL_SUBNET \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=mysql-nmstate}]' 'ResourceType=volume,Tags=[{Key=Name,Value=mysql-nmstate-disk}]' \
    --user-data file://mysql-apt.sh 2>&1 > /dev/null
echo "Done" ; echo " "

echo "Waiting 60s for instance to startup..."
sleep 60

INSTANCES=$(aws ec2 describe-instances --output json | jq -r ".Reservations[] | .Instances[] ")
while read -r i
do
  if [[ "$(echo $i | jq -r '.Tags[].Value')" == *"mysql-nmstate"* ]] && [[ "$(echo $i | jq -r '.State.Name')" == "running" ]] ; then
    MYSQL_ID=$(echo $i | jq -r '.InstanceId')
  fi
done < <(echo $INSTANCES | jq -c)
MYSQL_IP=$(aws ec2 describe-instances --instance-ids $MYSQL_ID --no-cli-pager | jq -r '.Reservations[].Instances[].PrivateIpAddress')


echo "########### Configuring mysql ###########" ; echo " "
ssh-add -k ~/.ssh/mysql-nmstate

sleep 30

exec ssh -R 10080:archive.ubuntu.com:80 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -t -A -q \
  -oProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -q -A -W %h:%p ubuntu@$BASTION_PUBLIC_IP" ubuntu@$MYSQL_IP \
  sudo -- "sh -c 'apt install mysql-server -y && sed -i "'"s/127.0.0.1/$(hostname -I)/"'" /etc/mysql/mysql.conf.d/mysqld.cnf && \
  systemctl restart mysql'" 2>&1 > /dev/null

ssh-add -D ~/.ssh/mysql-nmstate