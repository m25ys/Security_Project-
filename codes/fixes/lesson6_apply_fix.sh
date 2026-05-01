#!/bin/bash
# =============================================================
# LESSON 6 FIX: Apply Rate Limiting to Billing Endpoint
# 1. Creates an API Gateway Usage Plan with rate+burst limits
# 2. Creates an API Key associated with the Usage Plan
# 3. Optionally sets Lambda reserved concurrency for billing
# =============================================================

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 6: Applying Rate Limiting Fix"
echo "=========================================="

# -------------------------------------------------------
# STEP 1: Get the API Gateway ID and Stage name
# -------------------------------------------------------
echo ""
echo "[STEP 1] Finding DVSA API Gateway..."

API_GW_ID=$(aws apigateway get-rest-apis \
  --region "$AWS_REGION" \
  --query 'items[?contains(name, `DVSA`) || contains(name, `dvsa`)].id' \
  --output text 2>/dev/null | awk '{print $1}')

if [ -z "$API_GW_ID" ]; then
    echo "   Could not auto-detect API ID. Enter your API Gateway ID:"
    read -r API_GW_ID
fi

# Detect stage name (Stage or Prod)
STAGE_NAME=$(aws apigateway get-stages \
  --rest-api-id "$API_GW_ID" \
  --region "$AWS_REGION" \
  --query 'item[0].stageName' \
  --output text 2>/dev/null)

STAGE_NAME="${STAGE_NAME:-Stage}"

echo "   API ID    : $API_GW_ID"
echo "   Stage Name: $STAGE_NAME"

# -------------------------------------------------------
# STEP 2: Create a Usage Plan with rate limiting
# -------------------------------------------------------
echo ""
echo "[STEP 2] Creating usage plan with rate limits..."

USAGE_PLAN=$(aws apigateway create-usage-plan \
  --name "dvsa-billing-rate-limit" \
  --description "Prevents DoS on billing endpoint - ICS344 fix" \
  --api-stages "apiId=${API_GW_ID},stage=${STAGE_NAME}" \
  --throttle "{
    \"/order/POST\": {
      \"burstLimit\": 5,
      \"rateLimit\": 2.0
    }
  }" \
  --quota "limit=100,offset=0,period=DAY" \
  --region "$AWS_REGION" 2>/dev/null)

USAGE_PLAN_ID=$(echo "$USAGE_PLAN" | jq -r '.id // empty')

if [ -n "$USAGE_PLAN_ID" ]; then
    echo "   ✅ Usage plan created: $USAGE_PLAN_ID"
    echo "   Rate limit : 2 requests/second on /order POST"
    echo "   Burst limit: 5 requests"
    echo "   Daily quota: 100 requests per key"
else
    echo "   ⚠️  Usage plan creation failed or plan already exists."
    echo "   Response: $USAGE_PLAN"
fi

# -------------------------------------------------------
# STEP 3: Enable default method throttling on billing path
# (works without usage plans — applies to all callers)
# -------------------------------------------------------
echo ""
echo "[STEP 3] Setting default stage throttling on billing endpoint..."

aws apigateway update-stage \
  --rest-api-id "$API_GW_ID" \
  --stage-name "$STAGE_NAME" \
  --patch-operations \
    "op=replace,path=/defaultRouteSettings/throttlingBurstLimit,value=10" \
    "op=replace,path=/defaultRouteSettings/throttlingRateLimit,value=5" \
  --region "$AWS_REGION" 2>/dev/null && \
  echo "   ✅ Stage-level throttling set (burst=10, rate=5/sec)." || \
  echo "   ℹ️  Stage throttling update (may need manual configuration in Console)."

# -------------------------------------------------------
# STEP 4: Set Lambda Reserved Concurrency for billing function
# This isolates the billing path and prevents it consuming
# the entire account concurrency pool
# -------------------------------------------------------
echo ""
echo "[STEP 4] Setting reserved concurrency on billing-related Lambda..."

BILLING_LAMBDA="DVSA-ORDER-MANAGER"
RESERVED_CONCURRENCY=10   # Limit concurrent billing executions

aws lambda put-function-concurrency \
  --function-name "$BILLING_LAMBDA" \
  --reserved-concurrent-executions "$RESERVED_CONCURRENCY" \
  --region "$AWS_REGION" 2>/dev/null && \
  echo "   ✅ Reserved concurrency set to $RESERVED_CONCURRENCY for $BILLING_LAMBDA." || \
  echo "   ⚠️  Could not set concurrency. Check Lambda name."

# -------------------------------------------------------
# STEP 5: Verify configuration
# -------------------------------------------------------
echo ""
echo "[STEP 5] Verifying Lambda concurrency setting..."
aws lambda get-function-concurrency \
  --function-name "$BILLING_LAMBDA" \
  --region "$AWS_REGION" 2>/dev/null | jq '.'

echo ""
echo "=========================================="
echo " Fix applied. Now run: bash lesson6/verify_fix.sh"
echo "=========================================="
