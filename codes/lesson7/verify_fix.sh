#!/bin/bash

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 7: Over-Privileged Functions - Fix Verification"
echo "=========================================="

FUNCTION_NAME="DVSA-SEND-RECEIPT-EMAIL"

ROLE_ARN=$(aws lambda get-function-configuration \
  --function-name "$FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --query 'Role' --output text 2>/dev/null)
ROLE_NAME=$(echo "$ROLE_ARN" | sed 's/.*role\///')

echo "   Role: $ROLE_NAME"

echo ""
echo "[TEST 1] S3 GetObject/PutObject on arbitrary bucket (should be DENIED)..."

S3_SIM=$(aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "s3:GetObject" "s3:PutObject" \
  --resource-arns "arn:aws:s3:::some-unrelated-bucket/some-key" \
  --region "$AWS_REGION" 2>/dev/null)

echo "$S3_SIM" | jq '.EvaluationResults[] | {Action: .EvalActionName, Decision: .EvalDecision}'

S3_ALLOWED=$(echo "$S3_SIM" | jq '[.EvaluationResults[] | select(.EvalDecision == "allowed")] | length')
if [ "$S3_ALLOWED" -eq 0 ]; then
    echo "   ✅ FIXED: S3 access on arbitrary buckets is now DENIED."
else
    echo "   ❌ S3 access on arbitrary buckets is still ALLOWED ($S3_ALLOWED actions)."
fi

echo ""
echo "[TEST 2] DynamoDB Scan/DeleteItem on arbitrary table (should be DENIED)..."

DDB_SIM=$(aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "dynamodb:Scan" "dynamodb:DeleteItem" "dynamodb:PutItem" \
  --resource-arns "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/some-other-table" \
  --region "$AWS_REGION" 2>/dev/null)

echo "$DDB_SIM" | jq '.EvaluationResults[] | {Action: .EvalActionName, Decision: .EvalDecision}'

DDB_ALLOWED=$(echo "$DDB_SIM" | jq '[.EvaluationResults[] | select(.EvalDecision == "allowed")] | length')
if [ "$DDB_ALLOWED" -eq 0 ]; then
    echo "   ✅ FIXED: DynamoDB access on arbitrary tables is now DENIED."
else
    echo "   ❌ DynamoDB access on arbitrary tables is still ALLOWED ($DDB_ALLOWED actions)."
fi

echo ""
echo "[TEST 3] S3 GetObject on DVSA receipts bucket (should be ALLOWED)..."

RECEIPTS_SIM=$(aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "s3:GetObject" "s3:PutObject" \
  --resource-arns "arn:aws:s3:::${RECEIPTS_BUCKET}/some-receipt.pdf" \
  --region "$AWS_REGION" 2>/dev/null)

echo "$RECEIPTS_SIM" | jq '.EvaluationResults[] | {Action: .EvalActionName, Decision: .EvalDecision}'

RECEIPTS_OK=$(echo "$RECEIPTS_SIM" | jq '[.EvaluationResults[] | select(.EvalDecision == "allowed")] | length')
if [ "$RECEIPTS_OK" -gt 0 ]; then
    echo "   ✅ Receipts bucket access is still ALLOWED — function works normally."
else
    echo "   ⚠️  Receipts bucket access is DENIED — fix may be too restrictive."
fi

echo ""
echo "[TEST 4] DynamoDB GetItem on DVSA-ORDERS-DB (should be ALLOWED)..."

DVSA_DDB_SIM=$(aws iam simulate-principal-policy \
  --policy-source-arn "$ROLE_ARN" \
  --action-names "dynamodb:GetItem" "dynamodb:Query" \
  --resource-arns "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/DVSA-ORDERS-DB" \
  --region "$AWS_REGION" 2>/dev/null)

echo "$DVSA_DDB_SIM" | jq '.EvaluationResults[] | {Action: .EvalActionName, Decision: .EvalDecision}'

DVSA_DDB_OK=$(echo "$DVSA_DDB_SIM" | jq '[.EvaluationResults[] | select(.EvalDecision == "allowed")] | length')
if [ "$DVSA_DDB_OK" -gt 0 ]; then
    echo "   ✅ DVSA DynamoDB access still ALLOWED — function works normally."
else
    echo "   ⚠️  DVSA DynamoDB access DENIED — fix may be too restrictive."
fi

echo ""
echo "[TEST 5] Checking AmazonSESFullAccess is removed..."

MANAGED=$(aws iam list-attached-role-policies \
  --role-name "$ROLE_NAME" \
  --region "$AWS_REGION" 2>/dev/null | \
  jq -r '.AttachedPolicies[].PolicyName')

echo "   Attached managed policies:"
echo "$MANAGED" | sed 's/^/     /'

if echo "$MANAGED" | grep -qi "AmazonSESFullAccess"; then
    echo "   ❌ AmazonSESFullAccess is still attached — remove it."
else
    echo "   ✅ AmazonSESFullAccess has been removed."
fi

echo ""
echo "=========================================="
echo " Lesson 7 fix verification complete."
echo "=========================================="
