#!/usr/bin/env bash
#
# create_security_group.sh
# Creates a security group allowing SSH (22) restricted to the caller's
# current public IP, and HTTP (80) open to the internet.
#
# Usage:
#   ./create_security_group.sh [ssh-cidr]
#
# If ssh-cidr is not provided, the script auto-detects your current public
# IP and restricts SSH access to it (as a /32). Pass "0.0.0.0/0" explicitly
# if you deliberately want SSH open to the internet (not recommended).

# exits immediately if a command exits with a non-zero status, if an undefined variable is used, or if any command in a pipeline fails
set -euo pipefail

# Variables
PROFILE="devops-lab"
REGION="us-east-1"
VPC_ID="vpc-098b9b7d106e2b284"   # from: aws ec2 describe-vpcs
SG_NAME="devops-sg"
SG_DESCRIPTION="DevOps lab security group: SSH (restricted) + HTTP (public)"
PROJECT_TAG="AutomationLab"
STATE_DIR="${PWD}/.lab-state"

mkdir -p "$STATE_DIR"

# ---------------------------------------------------------------------------
# Determine the CIDR to allow SSH from
# ---------------------------------------------------------------------------
if [[ $# -ge 1 ]]; then
  SSH_CIDR="$1"
  echo "Using explicitly provided SSH CIDR: ${SSH_CIDR}"
else
  echo "No SSH CIDR provided. Auto-detecting your current public IP..."
  MY_IP=$(curl -s https://checkip.amazonaws.com)
  if [[ -z "$MY_IP" ]]; then
    echo "ERROR: Could not auto-detect your public IP. Pass a CIDR manually, e.g.:"
    echo "  ./create_security_group.sh 203.0.113.42/32"
    exit 1
  fi
  SSH_CIDR="${MY_IP}/32"
  echo "Detected public IP: ${MY_IP} -> restricting SSH to ${SSH_CIDR}"
fi

# ---------------------------------------------------------------------------
# check if the security group already exists, and create it if not
# ---------------------------------------------------------------------------
EXISTING_SG_ID=$(aws ec2 describe-security-groups \
  --profile "$PROFILE" --region "$REGION" \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text)

if [[ "$EXISTING_SG_ID" != "None" && -n "$EXISTING_SG_ID" ]]; then
  echo "Security group '${SG_NAME}' already exists: ${EXISTING_SG_ID}"
  SG_ID="$EXISTING_SG_ID"
else
  echo "Creating security group '${SG_NAME}'..."
  SG_ID=$(aws ec2 create-security-group \
    --profile "$PROFILE" --region "$REGION" \
    --group-name "$SG_NAME" \
    --description "$SG_DESCRIPTION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=${PROJECT_TAG}}]" \
    --query 'GroupId' --output text)
  echo "Created security group: ${SG_ID}"
fi

# ---------------------------------------------------------------------------
# Ingress rules: only add a rule if it doesn't already exist, to keep this
# script safe to re-run without erroring on "rule already exists"
# ---------------------------------------------------------------------------
rule_exists() {
  local port="$1" cidr="$2"
  aws ec2 describe-security-groups \
    --profile "$PROFILE" --region "$REGION" \
    --group-ids "$SG_ID" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`${port}\`] | [0].IpRanges[?CidrIp=='${cidr}']" \
    --output text | grep -q "$cidr"
}

if rule_exists 22 "$SSH_CIDR"; then
  echo "SSH ingress rule for ${SSH_CIDR} already present. Skipping."
else
  echo "Authorizing SSH (22) from ${SSH_CIDR}..."
  aws ec2 authorize-security-group-ingress \
    --profile "$PROFILE" --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr "$SSH_CIDR" >/dev/null
fi

if rule_exists 80 "0.0.0.0/0"; then
  echo "HTTP ingress rule for 0.0.0.0/0 already present. Skipping."
else
  echo "Authorizing HTTP (80) from 0.0.0.0/0 (public, by design)..."
  aws ec2 authorize-security-group-ingress \
    --profile "$PROFILE" --region "$REGION" \
    --group-id "$SG_ID" \
    --protocol tcp --port 80 --cidr "0.0.0.0/0" >/dev/null
fi

# ---------------------------------------------------------------------------
# Save state for other scripts, and display the final rule set
# ---------------------------------------------------------------------------
echo "$SG_ID" > "${STATE_DIR}/sg_id.txt"

echo "-----------------------------------------"
echo "Security Group ID : ${SG_ID}"
echo "State saved        : ${STATE_DIR}/sg_id.txt"
echo "Current rules:"
aws ec2 describe-security-groups \
  --profile "$PROFILE" --region "$REGION" \
  --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[].[FromPort,ToPort,IpProtocol,IpRanges[0].CidrIp]' \
  --output table
echo "-----------------------------------------"