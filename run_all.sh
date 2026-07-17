# ---------------------------------------------------------------------------
# run_all.sh
# Usage:
#   ./run_all.sh
#
# This script runs the other scripts in the correct order to create the lab's
# resources: security group, EC2 instance, and S3 bucket.
set -euo pipefail

echo "==============================="
echo "Creating security group..."
./create_security_group.sh 

echo "==============================="
echo "Creating EC2 instance..."
./create_ec2.sh $(cat .lab-state/sg_id.txt)

echo "==============================="
echo "Creating S3 bucket..."
./create_s3_bucket.sh

echo "==============================="
echo "All resources created successfully."
echo -e "=============================== \n\n"

echo "==============================="
echo "Summary of created resources:"
echo "Security group ID: $(cat .lab-state/sg_id.txt)"
echo "EC2 instance ID: $(cat .lab-state/instance_id.txt)"
echo "S3 bucket name: $(cat .lab-state/bucket_name.txt)"
echo "==============================="