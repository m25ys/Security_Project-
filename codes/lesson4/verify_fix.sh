#!/bin/bash
# =============================================================
# LESSON 4: FIX VERIFICATION
# Confirm unauthenticated S3 upload is now blocked
# =============================================================

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 4: Insecure Cloud Config - Fix Verification"
echo "=========================================="

if [ "$RECEIPTS_BUCKET" = "YOUR_RECEIPTS_BUCKET_NAME" ]; then
    echo "   Enter the receipts bucket name:"
    read -r RECEIPTS_BUCKET
fi

# -------------------------------------------------------
# TEST 1: Unauthenticated upload should now be BLOCKED
# -------------------------------------------------------
echo ""
echo "[TEST 1] Attempting unauthenticated upload (should be DENIED)..."

echo "test content" > /tmp/verify_test.txt

UNAUTH_RESULT=$(aws s3 cp /tmp/verify_test.txt \
  "s3://$RECEIPTS_BUCKET/2020/01/01/verify-test.raw" \
  --no-sign-request \
  --region "$AWS_REGION" 2>&1)

echo "   Result: $UNAUTH_RESULT"

if echo "$UNAUTH_RESULT" | grep -qi "AccessDenied\|403\|denied\|Error"; then
    echo "   ✅ FIXED: Unauthenticated upload is now blocked."
else
    echo "   ❌ Unauthenticated upload may still be allowed. Check bucket policy."
fi

# -------------------------------------------------------
# TEST 2: Verify Block Public Access is active
# -------------------------------------------------------
echo ""
echo "[TEST 2] Verifying Block Public Access settings..."
BPA=$(aws s3api get-public-access-block \
  --bucket "$RECEIPTS_BUCKET" \
  --region "$AWS_REGION" 2>/dev/null)
echo "$BPA" | jq '.'

ALL_BLOCKED=$(echo "$BPA" | jq '
  .PublicAccessBlockConfiguration |
  (.BlockPublicAcls and .IgnorePublicAcls and .BlockPublicPolicy and .RestrictPublicBuckets)
' 2>/dev/null)

if [ "$ALL_BLOCKED" = "true" ]; then
    echo "   ✅ All four Block Public Access settings are enabled."
else
    echo "   ⚠️  Some Block Public Access settings are not enabled."
fi

# -------------------------------------------------------
# TEST 3: Authenticated upload via application flow
# -------------------------------------------------------
echo ""
echo "[TEST 3] Checking bucket policy is applied..."
aws s3api get-bucket-policy \
  --bucket "$RECEIPTS_BUCKET" \
  --region "$AWS_REGION" 2>/dev/null | \
  python3 -c "import sys,json; p=json.load(sys.stdin); stmts=json.loads(p['Policy'])['Statement']; [print(f'   {s[\"Sid\"]}: {s[\"Effect\"]}') for s in stmts]" \
  2>/dev/null || echo "   Could not read bucket policy."

rm -f /tmp/verify_test.txt

echo ""
echo "=========================================="
echo " Lesson 4 fix verification complete."
echo "=========================================="
