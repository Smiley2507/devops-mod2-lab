#!/usr/bin/env bash
#
# cleanup_resources.sh
# Deletes the lab's EC2 instance, key pair, security group, and S3 bucket (including all object versions).
set -euo pipefail

PROFILE="devops-lab"
REGION="us-east-1"
STATE_DIR="${PWD}/.lab-state"

echo "This will permanently delete the lab's EC2 instance, key pair,"
echo "security group, and S3 bucket (including all object versions)."
read -rp "Type 'Yes,Delete Everything' to continue: " CONFIRM
if [[ "$CONFIRM" != "Yes,Delete Everything" ]]; then
  echo "Aborted. Nothing was deleted."
  exit 0
fi

# ---------------------------------------------------------------------------
# Terminate the EC2 instance (if it exists).
# ---------------------------------------------------------------------------
if [[ -f "${STATE_DIR}/instance_id.txt" ]]; then
  INSTANCE_ID=$(cat "${STATE_DIR}/instance_id.txt")
  echo "Terminating instance ${INSTANCE_ID}..."
  aws ec2 terminate-instances --profile "$PROFILE" --region "$REGION" \
    --instance-ids "$INSTANCE_ID" >/dev/null
  echo "Waiting for termination to complete..."
  aws ec2 wait instance-terminated --profile "$PROFILE" --region "$REGION" \
    --instance-ids "$INSTANCE_ID"
  echo "Instance terminated."
else
  echo "No instance_id.txt found. Skipping instance termination."
fi

# ---------------------------------------------------------------------------
# Delete the key pair (AWS side only — local .pem file is left alone).
# ---------------------------------------------------------------------------
KEY_NAME="devops-lab-key"
if aws ec2 describe-key-pairs --profile "$PROFILE" --region "$REGION" \
     --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Deleting key pair ${KEY_NAME}..."
  aws ec2 delete-key-pair --profile "$PROFILE" --region "$REGION" --key-name "$KEY_NAME"
else
  echo "Key pair ${KEY_NAME} not found. Skipping."
fi

# ---------------------------------------------------------------------------
# 3. Delete the security group.
# ---------------------------------------------------------------------------
if [[ -f "${STATE_DIR}/sg_id.txt" ]]; then
  SG_ID=$(cat "${STATE_DIR}/sg_id.txt")
  echo "Deleting security group ${SG_ID}..."
  aws ec2 delete-security-group --profile "$PROFILE" --region "$REGION" --group-id "$SG_ID"
else
  echo "No sg_id.txt found. Skipping security group deletion."
fi

# ---------------------------------------------------------------------------
# 4. Empty the S3 bucket (all versions + delete markers, since versioning
#    is enabled) and then delete the bucket itself.
# ---------------------------------------------------------------------------
if [[ -f "${STATE_DIR}/bucket_name.txt" ]]; then
  BUCKET_NAME=$(cat "${STATE_DIR}/bucket_name.txt")
  echo "Emptying bucket ${BUCKET_NAME} (deleting all object versions and delete markers)..."

  aws s3api list-object-versions --profile "$PROFILE" --bucket "$BUCKET_NAME" \
    --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' > "${STATE_DIR}/versions.json"
  if [[ $(jq '.Objects | length' "${STATE_DIR}/versions.json" 2>/dev/null || echo 0) -gt 0 ]]; then
    aws s3api delete-objects --profile "$PROFILE" --bucket "$BUCKET_NAME" \
      --delete "file://${STATE_DIR}/versions.json" >/dev/null
  fi

  aws s3api list-object-versions --profile "$PROFILE" --bucket "$BUCKET_NAME" \
    --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' > "${STATE_DIR}/markers.json"
  if [[ $(jq '.Objects | length' "${STATE_DIR}/markers.json" 2>/dev/null || echo 0) -gt 0 ]]; then
    aws s3api delete-objects --profile "$PROFILE" --bucket "$BUCKET_NAME" \
      --delete "file://${STATE_DIR}/markers.json" >/dev/null
  fi

  echo "Deleting bucket ${BUCKET_NAME}..."
  aws s3api delete-bucket --profile "$PROFILE" --bucket "$BUCKET_NAME"
else
  echo "No bucket_name.txt found. Skipping bucket deletion."
fi

echo "-----------------------------------------"
echo "Cleanup complete."
echo "-----------------------------------------"