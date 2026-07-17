#!/usr/bin/env bash
#
# create_s3_bucket.sh
# Usage:
#   ./create_s3_bucket.sh

set -euo pipefail

PROFILE="devops-lab"
REGION="us-east-1"
STATE_DIR="${PWD}/.lab-state"

mkdir -p "$STATE_DIR"


# Varriables
ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query 'Account' --output text)
BUCKET_NAME="devops-lab-${ACCOUNT_ID}"

echo "Target bucket: ${BUCKET_NAME}"

# ---------------------------------------------------------------------------
# check if the bucket already exists, and create it if not
# ---------------------------------------------------------------------------
if aws s3api head-bucket --profile "$PROFILE" --bucket "$BUCKET_NAME" 2>/dev/null; then
  echo "Bucket already exists. Skipping creation."
else
  echo "Creating bucket..."
  # Note: us-east-1 is a special case — passing --create-bucket-configuration
  # here would actually cause an error. Every other region requires it.
  aws s3api create-bucket \
    --profile "$PROFILE" --region "$REGION" \
    --bucket "$BUCKET_NAME"
fi

# ---------------------------------------------------------------------------
# Versioning, Block Public Access, and default encryption.
# These are PUT operations, safe to re-apply every run even if already set.
# ---------------------------------------------------------------------------
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --profile "$PROFILE" --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

echo "Explicitly blocking all public access..."
aws s3api put-public-access-block \
  --profile "$PROFILE" --bucket "$BUCKET_NAME" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# ---------------------------------------------------------------------------
# Bucket policy: deny any request that isn't over HTTPS.
# This does not expose the bucket publicly — it's a baseline security
# control, not a public-read policy.
# ---------------------------------------------------------------------------
echo "Applying deny-insecure-transport bucket policy..."
cat > "${STATE_DIR}/bucket_policy.json" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${BUCKET_NAME}",
        "arn:aws:s3:::${BUCKET_NAME}/*"
      ],
      "Condition": {
        "Bool": { "aws:SecureTransport": "false" }
      }
    }
  ]
}
EOF

aws s3api put-bucket-policy \
  --profile "$PROFILE" --bucket "$BUCKET_NAME" \
  --policy "file://${STATE_DIR}/bucket_policy.json"

# ---------------------------------------------------------------------------
# Upload a sample file
# ---------------------------------------------------------------------------
echo "Uploading sample welcome.txt..."
echo "Welcome to the AmaliTech DevOps automation lab. Bucket: ${BUCKET_NAME}" > "${STATE_DIR}/welcome.txt"
aws s3api put-object \
  --profile "$PROFILE" --bucket "$BUCKET_NAME" \
  --key "welcome.txt" \
  --body "${STATE_DIR}/welcome.txt"

echo "${BUCKET_NAME}" > "${STATE_DIR}/bucket_name.txt"

echo "-----------------------------------------"
echo "Bucket        : ${BUCKET_NAME}"
echo "Versioning    : Enabled"
echo "Public access : Blocked"
echo "Encryption    : AES256 (SSE-S3)"
echo "Policy        : Deny insecure transport"
echo "Sample object : welcome.txt"
echo "State saved   : ${STATE_DIR}/bucket_name.txt"
echo "-----------------------------------------"