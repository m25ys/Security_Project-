#!/bin/bash
# =============================================================
# LESSON 3: FIX VERIFICATION
# Confirm receipt access is now restricted to order owner only
# =============================================================

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../helpers/create_order.sh"

echo "=========================================="
echo " LESSON 3: Sensitive Disclosure - Fix Verification"
echo "=========================================="

guard_token "TOKEN_B"
guard_token "TOKEN_C"

# -------------------------------------------------------
# TEST 1: User B should NOT get User C's receipt (must fail)
# -------------------------------------------------------
echo ""
echo "[TEST 1] User B requesting User C's receipt (should be DENIED)..."

# Get a victim order-id — from Lesson 2 if available, or prompt
if [ -z "$ORDER_C" ]; then
    echo "   Enter User C's order-id:"
    read -r ORDER_C
fi

CROSS_RECEIPT=$(curl -s -X POST "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get-receipt\",\"order-id\":\"$ORDER_C\"}")

echo "   Response: $CROSS_RECEIPT"

if echo "$CROSS_RECEIPT" | grep -qi "access denied\|forbidden\|403\|err"; then
    echo "   ✅ FIXED: Cross-user receipt access correctly denied."
else
    echo "   ❌ Fix may not be applied — User B still got a response for User C's order."
fi

# -------------------------------------------------------
# TEST 2: User B SHOULD get their own receipt (must succeed)
# -------------------------------------------------------
echo ""
echo "[TEST 2] User B requesting their own receipt (should SUCCEED)..."

# Create a fresh order for User B
create_order_with_shipping "TOKEN_B" "verify-receipt-cart" 1
OWNED_ORDER_ID="$ORDER_ID"

OWN_RECEIPT=$(curl -s -X POST "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get-receipt\",\"order-id\":\"$OWNED_ORDER_ID\"}")

echo "   Response: $OWN_RECEIPT"

if echo "$OWN_RECEIPT" | grep -qi "url\|ok\|https"; then
    echo "   ✅ Legitimate receipt access still works."
else
    echo "   ⚠️  Could not retrieve own receipt - check order is in 'shipped' state."
fi

# -------------------------------------------------------
# TEST 3: No receipt URL should be returned for non-existent order
# -------------------------------------------------------
echo ""
echo "[TEST 3] Requesting receipt for non-existent order-id..."
FAKE_RECEIPT=$(curl -s -X POST "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw '{"action":"get-receipt","order-id":"this-order-does-not-exist"}')
echo "   Response: $FAKE_RECEIPT"

if echo "$FAKE_RECEIPT" | grep -qi "not found\|404\|err"; then
    echo "   ✅ Non-existent order correctly returns error."
else
    echo "   ⚠️  Unexpected response for non-existent order."
fi

echo ""
echo "=========================================="
echo " Lesson 3 fix verification complete."
echo "=========================================="
