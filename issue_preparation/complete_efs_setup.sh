#!/bin/bash

# $1 - ID of subnet to create the first EFS mount target in
# $2 - ID of subnet to create the second EFS mount target in

vpc_id=$(aws eks describe-cluster \
    --name my-demo-cluster \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

cidr_range=$(aws ec2 describe-vpcs \
    --vpc-ids $vpc_id \
    --query "Vpcs[].CidrBlock" \
    --output text \
    --region eu-central-1)

security_group_id=$(aws ec2 create-security-group \
    --group-name MyEfsSecurityGroup \
    --description "My EFS security group" \
    --vpc-id $vpc_id \
    --output text)

echo "Security group ID: $security_group_id"

aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $cidr_range

file_system_id=$(aws efs create-file-system \
    --region eu-central-1 \
    --performance-mode generalPurpose \
    --query 'FileSystemId' \
    --output text)

echo "Filesystem ID: $file_system_id"
echo "Sleeping to make sure FS is up before creating the mount targets..."

sleep 20

aws efs create-mount-target \
    --file-system-id $file_system_id \
    --subnet-id $1 \
    --security-groups $security_group_id

aws efs create-mount-target \
    --file-system-id $file_system_id \
    --subnet-id $2 \
    --security-groups $security_group_id