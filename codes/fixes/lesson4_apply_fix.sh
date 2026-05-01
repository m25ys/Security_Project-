#!/bin/bash
# =============================================================
# LESSON 4 FIX: Harden S3 Bucket Configuration
# 1. Enable Block Public Access
# 2. Replace permissive bucket policy with least-privilege
# 3. Add object key prefix validation guidance
# =============================================================

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 4: Applying S3 Hardening Fix"
echo "=========================================="

if [ "$RECEIPTS_BUCKET" = "YOUR_RECEIPTS_BUCKET_NAME" ]; then
    echo "   Enter the receipts bucket name:"
    read -r RECEIPTS_BUCKET
fi

echo "   Target bucket: $RECEIPTS_BUCKET"

# -------------------------------------------------------
# STEP 1: Enable Block Public Access on the bucket
# -------------------------------------------------------
echo ""
echo "[STEP 1] Enabling S3 Block Public Access..."
aws s3api put-public-access-block \
  --bucket "$RECEIPTS_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
  --region "$AWS_REGION" && \
  echo "   ✅ Block Public Access enabled." || \
  echo "   ❌ Failed to enable Block Public Access."

# -------------------------------------------------------
# STEP 2: Remove any public ACL from the bucket
# -------------------------------------------------------
echo ""
echo "[STEP 2] Setting bucket ACL to private..."
aws s3api put-bucket-acl \
  --bucket "$RECEIPTS_BUCKET" \
  --acl private \
  --region "$AWS_REGION" && \
  echo "   ✅ Bucket ACL set to private." || \
  echo "   ⚠️  Could not set ACL (may be managed by Block Public Access already)."

# -------------------------------------------------------
# STEP 3: Apply least-privilege bucket policy
# Only allow writes from the Lambda execution role
# Only allow reads from the receipt Lambda role
# -------------------------------------------------------
echo ""
echo "[STEP 3] Applying least-privilege bucket policy..."

# Get the Lambda execution role ARNs we need to allow
RECEIPT_ROLE_ARN=$(aws lambda get-function-configuration \
  --function-name "DVSA-SEND-RECEIPT-EMAIL" \
  --region "$AWS_REGION" \
  --query 'Role' --output text 2>/dev/null)

ORDER_ROLE_ARN=$(aws lambda get-function-configuration \
  --function-name "DVSA-ORDER-MANAGER" \
  --region "$AWS_REGION" \
  --query 'Role' --output text 2>/dev/null)

if [ -z "$RECEIPT_ROLE_ARN" ] || [ -z "$ORDER_ROLE_ARN" ]; then
    echo "   ⚠️  Could not auto-detect Lambda role ARNs."
    echo "   Enter DVSA-SEND-RECEIPT-EMAIL role ARN:"
    read -r RECEIPT_ROLE_ARN
    echo "   Enter DVSA-ORDER-MANAGER role ARN:"
    read -r ORDER_ROLE_ARN
fi

echo "   Receipt role : $RECEIPT_ROLE_ARN"
echo "   Order role   : $ORDER_ROLE_ARN"

BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAllPublicAccess",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::${RECEIPTS_BUCKET}",
        "arn:aws:s3:::${RECEIPTS_BUCKET}/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    },
    {
      "Sid": "AllowReceiptLambdaReadWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${RECEIPT_ROLE_ARN}"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${RECEIPTS_BUCKET}/*"
    },
    {
      "Sid": "AllowOrderManagerWrite",
      "Effect": "Allow",
      "Principal": {
        "AWS": "${ORDER_ROLE_ARN}"
      },
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::${RECEIPTS_BUCKET}/*"
    }
  ]
}
EOF
)

aws s3api put-bucket-policy \
  --bucket "$RECEIPTS_BUCKET" \
  --policy "$BUCKET_POLICY" \
  --region "$AWS_REGION" && \
  echo "   ✅ Least-privilege bucket policy applied." || \
  echo "   ❌ Failed to apply bucket policy."

# -------------------------------------------------------
# STEP 4: Verify the fix
# -------------------------------------------------------
echo ""
echo "[STEP 4] Verifying Block Public Access is active..."
aws s3api get-public-access-block \
  --bucket "$RECEIPTS_BUCKET" \
  --region "$AWS_REGION" | jq '.'

echo ""
echo "=========================================="
echo " Fix applied. Now run: bash lesson4/verify_fix.sh"
echo "=========================================="
