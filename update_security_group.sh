#!/usr/bin/env bash
#
# update_security_group.sh
# Small utility: attaches a security group to an already-running instance.

set -euo pipefail

PROFILE="devops-lab"
REGION="us-east-1"
STATE_DIR="${PWD}/.lab-state"

INSTANCE_ID=$(cat "${STATE_DIR}/instance_id.txt")
SG_ID=$(cat "${STATE_DIR}/sg_id.txt")

echo "Attaching ${SG_ID} to ${INSTANCE_ID}..."
aws ec2 modify-instance-attribute \
  --profile "$PROFILE" --region "$REGION" \
  --instance-id "$INSTANCE_ID" \
  --groups "$SG_ID"

echo "Done. Instance's security groups are now:"
aws ec2 describe-instances \
  --profile "$PROFILE" --region "$REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text