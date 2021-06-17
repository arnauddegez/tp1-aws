#!/bin/bash

#identification aws
#aws configure import --csv file://credentials.csv

#Variables
VPC_CIDR="10.15.0.0/16"
VPC_NAME="vpcdearnaud"
SUBNET_PUBLIC_CIDR="10.15.1.0/24"
SUBNET_PUBLIC_AZ="eu-west-3a"
SUBNET_PRIVATE_CIDR="10.15.2.0/24"
SUBNET_PRIVATE_AZ="eu-west-3b"
KEYPAIR="wordpress"
GROUP_NAME="wordpresssecure"
AMI_ID="/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"


# Create VPC
echo "Creating VPC ..."
VPC_ID=$(aws ec2 create-vpc \
--cidr-block $VPC_CIDR \
--query 'Vpc.{VpcId:VpcId}' \
--output text )
echo "  VPC ID '$VPC_ID' CREATED"

# Add Name tag to VPC
aws ec2 create-tags \
--resources $VPC_ID \
--tags "Key=Name,Value=$VPC_NAME"
echo "  VPC ID '$VPC_ID' NAMED as '$VPC_NAME'."

# Create Public Subnet
echo "Creating Public Subnet..."
SUBNET_PUBLIC_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $SUBNET_PUBLIC_CIDR \
--availability-zone $SUBNET_PUBLIC_AZ \
--query 'Subnet.{SubnetId:SubnetId}' \
--output text)
echo "  Subnet ID '$SUBNET_PUBLIC_ID' CREATED"

# Create Private Subnet
echo "Creating Private Subnet..."
SUBNET_PRIVATE_ID=$(aws ec2 create-subnet \
--vpc-id $VPC_ID \
--cidr-block $SUBNET_PRIVATE_CIDR \
--availability-zone $SUBNET_PRIVATE_AZ \
--query 'Subnet.{SubnetId:SubnetId}' \
--output text)
echo "  Subnet ID '$SUBNET_PRIVATE_ID' CREATED"

# Create Internet gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
--query 'InternetGateway.{InternetGatewayId:InternetGatewayId}' \
--output text)
echo "  Internet Gateway ID '$IGW_ID' CREATED."

# Attach Internet gateway to your VPC
aws ec2 attach-internet-gateway \
--vpc-id $VPC_ID \
--internet-gateway-id $IGW_ID
echo "  Internet Gateway ID '$IGW_ID' ATTACHED to VPC ID '$VPC_ID'."

# Create Route Table
echo "Creating Route Table..."
ROUTE_TABLE_ID=$(aws ec2 create-route-table \
--vpc-id $VPC_ID \
--query 'RouteTable.{RouteTableId:RouteTableId}' \
--output text)
echo "  Route Table ID '$ROUTE_TABLE_ID' CREATED."

# Create route to Internet Gateway
RESULT=$(aws ec2 create-route \
--route-table-id $ROUTE_TABLE_ID \
--destination-cidr-block 0.0.0.0/0 \
--gateway-id $IGW_ID)
echo "  Route to '0.0.0.0/0' via Internet Gateway ID '$IGW_ID' ADDED to" \
  "Route Table ID '$ROUTE_TABLE_ID'."

# Associate Public Subnet with Route Table
RESULT=$(aws ec2 associate-route-table \
--subnet-id $SUBNET_PUBLIC_ID \
--route-table-id $ROUTE_TABLE_ID)

echo "  Public Subnet ID '$SUBNET_PUBLIC_ID' ASSOCIATED with Route Table ID" \
"'$ROUTE_TABLE_ID'."

# Enable Auto-assign Public IP on Public Subnet
aws ec2 modify-subnet-attribute \
--subnet-id $SUBNET_PUBLIC_ID \
--map-public-ip-on-launch

echo "  'Auto-assign Public IP' ENABLED on Public Subnet ID" \
  "'$SUBNET_PUBLIC_ID'."

#DELETE OF THE SSH KEY IF EXISTING
if aws ec2 wait key-pair-exists --key-names $KEYPAIR
    then
    echo "la clé existe déjà, suppression"
    aws ec2 delete-key-pair --key-name $KEYPAIR
fi
#Create ssh keypair
aws ec2 create-key-pair \
--key-name $KEYPAIR \
--query "KeyMaterial" \
--output text > $KEYPAIR.pem
echo " Keypair named $KEYPAIR and file CREATED"



#Definition of the correct rights on the SSH key
chmod 400 $KEYPAIR.pem

#Create security group
GROUP_ID=$(aws ec2 create-security-group \
--group-name $GROUP_NAME \
--description "My wordpress security group" \
--vpc-id $VPC_ID \
--output text)

echo "Security group $GROUP_NAME CREATED"


#Autorise SSH port for security group
aws ec2 authorize-security-group-ingress \
--group-id $GROUP_ID \
--protocol tcp \
--port 22 \
--cidr 0.0.0.0/0

#Autorise http port for security group
aws ec2 authorize-security-group-ingress \
--group-id $GROUP_ID \
--protocol tcp \
--port 80 \
--cidr 0.0.0.0/0

echo "RULES OK"

#RUN Ec2 instance
INSTANCE_ID=$(aws ec2 run-instances \
--image-id resolve:ssm:$AMI_ID \
--count 1 \
--instance-type t2.micro \
--key-name $KEYPAIR \
--security-group-ids $GROUP_ID \
--subnet-id $SUBNET_PUBLIC_ID \
--query "InstanceId[0].InstanceId" \
--output text)

echo "Instance $INSTANCEID CREATED"

#DISPLAY PUBLIC IP ADDRESS
PUBLIC_IP=$(aws ec2 describe-instances \
--instance-ids $INSTANCE_ID \
--query "PublicIpAddress.{PublicIpAddress:PublicIpAddress}" \
--output text)

echo " PUBLIC IP is $PUBLIC_IP"