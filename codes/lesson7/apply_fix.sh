#!/bin/bash

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 7: Applying Least Privilege Fix"
echo "=========================================="

FUNCTION_NAME="DVSA-SEND-RECEIPT-EMAIL"

ROLE_ARN=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --query 'Role' --output text 2>/dev/null)

ROLE_NAME=$(echo "$ROLE_ARN" | sed 's/.*role\///')

echo "   Role: $ROLE_NAME"

echo ""
echo "[STEP 1] Detaching AmazonSESFullAccess..."
aws iam detach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSESFullAccess" \
  --region "$AWS_REGION" 2>/dev/null && \
  echo "   ✅ AmazonSESFullAccess detached." || \
  echo "   ℹ️  Already detached or not found."

echo ""
echo "[STEP 2] Creating least-privilege inline policy..."

POLICY_JSON=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3ReceiptsOnly",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": ["arn:aws:s3:::${RECEIPTS_BUCKET}/*"]
    },
    {
      "Sid": "DynamoDBDVSAOnly",
      "Effect": "Allow",
      "Action": ["dynamodb:GetItem", "dynamodb:Query"],
      "Resource": [
        "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/DVSA-ORDERS-DB",
        "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/DVSA-USERS-DB"
      ]
    },
    {
      "Sid": "SESSendOnly",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*"
    },
    {
      "Sid": "STSGetCallerIdentity",
      "Effect": "Allow",
      "Action": ["sts:GetCallerIdentity"],
      "Resource": "*"
    }
  ]
}
EOF
)

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "LeastPrivilegeReceiptPolicy" \
  --policy-document "$POLICY_JSON" \
  --region "$AWS_REGION" 2>/dev/null && \
  echo "   ✅ Least-privilege policy applied." || \
  echo "   ❌ Failed to apply policy. Check permissions."

echo ""
echo "=========================================="
echo " Fix applied. Now run lesson7/verify_fix.sh"
echo "=========================================="
