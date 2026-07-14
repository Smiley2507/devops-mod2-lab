#!/usr/bin/env bash
#
# create_ec2.sh
# Automates creation of an EC2 key pair + instance
#
# Usage:
#   ./create_ec2.sh [security-group-id]
#
# if no security group ID is provided, the script will use the default security group of the specified VPC.

# exits immediately if a command exits with a non-zero status, if an undefined variable is used, or if any command in a pipeline fails
set -euo pipefail

# Variables
PROFILE="devops-lab"
REGION="us-east-1"
KEY_NAME="devops-lab-key"
KEY_PATH="${HOME}/.ssh/${KEY_NAME}.pem"
INSTANCE_NAME="devops-lab-instance"
PROJECT_TAG="AutomationLab"
INSTANCE_TYPE="t3.micro"
VPC_ID="vpc-098b9b7d106e2b284"       # from: aws ec2 describe-vpcs 
SUBNET_ID="subnet-0434b3b8b2be6d26b"  # from: aws ec2 describe-subnets 
AMI_SSM_PARAM="/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"

# ---------------------------------------------------------------------------
# capture security group ID from command line argument, if provided
# ---------------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
  SG_ID="$1"
else
  echo "No security group ID passed as an argument. Falling back to the VPC's default security group."
  SG_ID=$(aws ec2 describe-security-groups \
    --profile "$PROFILE" --region "$REGION" \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=default" \
    --query 'SecurityGroups[0].GroupId' --output text)
fi

echo "Using security group: ${SG_ID}"

# ---------------------------------------------------------------------------
#check if an instance with the same name already exists
# ---------------------------------------------------------------------------
EXISTING_INSTANCE_ID=$(aws ec2 describe-instances \
  --profile "$PROFILE" \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=${INSTANCE_NAME}" \
            "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

if [[ "$EXISTING_INSTANCE_ID" != "None" && -n "$EXISTING_INSTANCE_ID" ]]; then
  echo "An instance named '${INSTANCE_NAME}' already exists: ${EXISTING_INSTANCE_ID}"
  echo "Skipping creation. Terminate it first (or via cleanup_resources.sh) if you want a fresh one."
  aws ec2 describe-instances \
    --profile "$PROFILE" --region "$REGION" \
    --instance-ids "$EXISTING_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress]' --output text
  exit 0
fi

# ---------------------------------------------------------------------------
# Key pair: create only if it doesn't already exist locally or in AWS
# ---------------------------------------------------------------------------
if aws ec2 describe-key-pairs --profile "$PROFILE" --region "$REGION" \
     --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair '${KEY_NAME}' already exists in AWS."
  if [[ ! -f "$KEY_PATH" ]]; then
    echo "WARNING: AWS has this key pair registered, but the .pem file isn't at ${KEY_PATH}."
    echo "You cannot recover the private key material. Delete the key pair in AWS and re-run this script to generate a new one."
    exit 1
  fi
else
  echo "Creating key pair '${KEY_NAME}'..."

# ---------------------------------------------------------------------------
# check if the .ssh directory exists, create it if not, and set permissions
# ---------------------------------------------------------------------------
  mkdir -p "$(dirname "$KEY_PATH")"
  chmod 700 "$(dirname "$KEY_PATH")"

  aws ec2 create-key-pair \
    --profile "$PROFILE" --region "$REGION" \
    --key-name "$KEY_NAME" \
    --query 'KeyMaterial' --output text > "$KEY_PATH"

  chmod 400 "$KEY_PATH"
  echo "Private key saved to ${KEY_PATH} with permissions set to 400 (owner read-only)."
fi

# ---------------------------------------------------------------------------
# Look up the latest Amazon Linux 2 AMI dynamically via SSM Parameter Store
# ---------------------------------------------------------------------------
echo "Looking up latest Amazon Linux 2 AMI for ${REGION}..."
AMI_ID=$(aws ssm get-parameter \
  --profile "$PROFILE" --region "$REGION" \
  --name "$AMI_SSM_PARAM" \
  --query 'Parameter.Value' --output text)

echo "Using AMI: ${AMI_ID}"

# ---------------------------------------------------------------------------
# Launch the instance
# ---------------------------------------------------------------------------
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --profile "$PROFILE" --region "$REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --subnet-id "$SUBNET_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}},{Key=Project,Value=${PROJECT_TAG}}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance launched: ${INSTANCE_ID}"
echo "Waiting for instance to reach 'running' state..."

aws ec2 wait instance-running \
  --profile "$PROFILE" --region "$REGION" \
  --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances \
  --profile "$PROFILE" --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "-----------------------------------------"
echo "Instance ID : ${INSTANCE_ID}"
echo "Public IP   : ${PUBLIC_IP}"
echo "SSH command : ssh -i ${KEY_PATH} ec2-user@${PUBLIC_IP}"
echo "-----------------------------------------"
