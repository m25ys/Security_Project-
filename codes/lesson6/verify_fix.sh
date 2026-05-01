#!/bin/bash
# =============================================================
# LESSON 6: FIX VERIFICATION
# Confirm rate limiting blocks the flood while legitimate
# requests still complete successfully
# =============================================================

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../helpers/create_order.sh"

echo "=========================================="
echo " LESSON 6: DoS - Fix Verification"
echo "=========================================="

guard_token "TOKEN_B"
guard_token "TOKEN_C"

# -------------------------------------------------------
# TEST 1: Flood should now hit 429 rate limit
# -------------------------------------------------------
echo ""
echo "[TEST 1] Sending 20 rapid concurrent requests (should hit rate limit)..."

rm -f /tmp/verify6_*.txt

for i in $(seq 1 20); do
    (curl -s -X POST "$API" \
      -H "content-type: application/json" \
      -H "authorization: $TOKEN_B" \
      --data-raw '{"action":"orders"}' \
      -w "\nHTTP_%{http_code}" \
      -o /tmp/verify6_${i}.txt) &
done
wait

TOTAL=0; THROTTLED=0; OK=0
for i in $(seq 1 20); do
    [ -f /tmp/verify6_${i}.txt ] || continue
    RESP=$(cat /tmp/verify6_${i}.txt)
    TOTAL=$((TOTAL+1))
    echo "$RESP" | grep -qi "429\|TooMany\|throttl" && THROTTLED=$((THROTTLED+1)) || OK=$((OK+1))
done

echo "   Total requests : $TOTAL"
echo "   Throttled (429): $THROTTLED"
echo "   Passed through : $OK"

if [ "$THROTTLED" -gt 0 ]; then
    echo "   ✅ FIXED: Rate limiting is active — some requests were throttled."
else
    echo "   ⚠️  No throttling detected yet. Check API Gateway usage plan settings."
fi

rm -f /tmp/verify6_*.txt

# -------------------------------------------------------
# TEST 2: Single legitimate request should still work
# -------------------------------------------------------
echo ""
echo "[TEST 2] Single legitimate request (should SUCCEED)..."
sleep 2  # Allow rate limit window to reset

START=$(date +%s%N)
LEGIT=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_C" \
  --data-raw '{"action":"orders"}')
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))

echo "   Response: $LEGIT"
echo "   Response time: ${MS}ms"

if echo "$LEGIT" | grep -qi "ok\|orders\|status"; then
    echo "   ✅ Legitimate request succeeded in ${MS}ms."
else
    echo "   ⚠️  Unexpected response — check if fix broke normal functionality."
fi

# -------------------------------------------------------
# TEST 3: Check Lambda reserved concurrency is set
# -------------------------------------------------------
echo ""
echo "[TEST 3] Checking Lambda concurrency setting..."
CONCURRENCY=$(aws lambda get-function-concurrency \
  --function-name "DVSA-ORDER-MANAGER" \
  --region "$AWS_REGION" 2>/dev/null | \
  jq -r '.ReservedConcurrentExecutions // "not set"')
echo "   DVSA-ORDER-MANAGER reserved concurrency: $CONCURRENCY"

if [ "$CONCURRENCY" != "not set" ] && [ "$CONCURRENCY" != "null" ]; then
    echo "   ✅ Reserved concurrency is configured."
else
    echo "   ⚠️  Reserved concurrency not set — run fixes/lesson6_apply_fix.sh"
fi

echo ""
echo "=========================================="
echo " Lesson 6 fix verification complete."
echo "=========================================="
