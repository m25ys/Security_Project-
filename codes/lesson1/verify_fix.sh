#!/bin/bash

source "$(dirname "$0")/../config.sh"

echo "=========================================="
echo " LESSON 1 & 9: Fix Verification"
echo "=========================================="

echo ""
echo "[TEST 1] Sending original RCE payload (should now be rejected)..."
RESPONSE=$(curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d '{
    "action": "_$$ND_FUNC$$_function(){ var fs = require(\"fs\"); fs.writeFileSync(\"/tmp/pwned2.txt\", \"still hacked\"); console.error(\"STILL VULNERABLE\"); }()",
    "cart-id": ""
  }')

echo "   Response: $RESPONSE"

if echo "$RESPONSE" | grep -qi "invalid\|error\|bad request\|400"; then
    echo "   ✅ FIXED: Payload was rejected at input validation stage."
else
    echo "   ⚠️  Check CloudWatch - if no FILE READ log appears, the fix worked."
    echo "      A generic 500 could still mean the function crashed safely."
fi

echo ""
echo "[TEST 2] Sending invalid action (should be rejected by allowlist)..."
RESPONSE2=$(curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -d '{"action": "DROP_TABLE_users", "cart-id": "test"}')
echo "   Response: $RESPONSE2"

echo ""
echo "[TEST 3] Sending valid action (should still work normally)..."
RESPONSE3=$(curl -s -X POST "${API_URL}/order" \
  -H "Content-Type: application/json" \
  -H "Authorization: ${TOKEN_B}" \
  -d '{"action": "orders"}')
echo "   Response: $RESPONSE3"

echo ""
echo "=========================================="
echo " Also verify in CloudWatch:"
echo " - No 'FILE READ SUCCESS' line in latest logs"
echo " - No '/tmp/pwned' file evidence"
echo "=========================================="
