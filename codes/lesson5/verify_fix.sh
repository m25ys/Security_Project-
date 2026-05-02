#!/bin/bash

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../helpers/create_order.sh"

echo "=========================================="
echo " LESSON 5: Broken Access Control - Fix Verification"
echo "=========================================="

guard_token "TOKEN_B"

echo ""
echo "[TEST 1] Attempting to bypass billing (should be BLOCKED)..."

create_order_with_shipping "TOKEN_B" "verify5-cart" 1
VERIFY_ORDER="$ORDER_ID"

echo "   Trying update-order action..."
R1=$(curl -s -X POST "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"update-order\",\"order-id\":\"$VERIFY_ORDER\",\"status\":\"paid\"}")
echo "   Response: $R1"

echo ""
echo "   Trying admin path..."
R2=$(curl -s -X POST "${API_URL}/order/admin" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"update\",\"order-id\":\"$VERIFY_ORDER\",\"status\":\"paid\"}" 2>/dev/null)
echo "   Response: $R2"

echo ""
echo "[TEST 1 CHECK] Verifying order status after bypass attempts..."
sleep 1
ORDER_STATE=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get\",\"order-id\":\"$VERIFY_ORDER\"}")
STATUS=$(echo "$ORDER_STATE" | jq -r '.order.status // .status // "unknown"')
echo "   Order status: $STATUS"

if [ "$STATUS" = "paid" ]; then
    echo "   ❌ Fix NOT effective — order was marked paid without billing."
else
    echo "   ✅ FIXED: Order status is '$STATUS' — bypass was blocked."
fi

echo ""
echo "[TEST 2] Confirming legitimate billing flow still works..."

create_order_with_shipping "TOKEN_B" "verify5-legit-cart" 1
LEGIT_ORDER="$ORDER_ID"

BILL=$(curl -s -X POST "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{
    \"action\": \"billing\",
    \"order-id\": \"$LEGIT_ORDER\",
    \"data\": {\"ccn\": \"4242424242424242\", \"exp\": \"12/25\", \"cvv\": \"123\"}
  }")
echo "   Billing response: $BILL"

sleep 2
LEGIT_STATE=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get\",\"order-id\":\"$LEGIT_ORDER\"}" | \
  jq -r '.order.status // .status // "unknown"')
echo "   Order status after legitimate billing: $LEGIT_STATE"

if [ "$LEGIT_STATE" = "paid" ] || [ "$LEGIT_STATE" = "complete" ]; then
    echo "   ✅ Legitimate billing flow still works correctly."
else
    echo "   ⚠️  Legitimate billing did not complete — check Lambda logs."
fi

echo ""
echo "=========================================="
echo " Lesson 5 fix verification complete."
echo "=========================================="
