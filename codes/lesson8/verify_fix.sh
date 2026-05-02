#!/bin/bash

source "$(dirname "$0")/../config.sh"
source "$(dirname "$0")/../helpers/create_order.sh"

echo "=========================================="
echo " LESSON 8: Logic Vulnerabilities - Fix Verification"
echo "=========================================="

guard_token "TOKEN_B"

echo ""
echo "[TEST 1] Attempting race condition (should be BLOCKED after fix)..."

create_order_with_shipping "TOKEN_B" "verify8-race-$(date +%s)" 1
VERIFY_ORDER="$ORDER_ID"
echo "   Order ID: $VERIFY_ORDER"

python3 - <<PYVERIFY
import os, threading, urllib.request, json, time

API     = os.environ["API"]
TOKEN_B = os.environ["TOKEN_B"]
ORDER_ID = "$VERIFY_ORDER"

results = {}
barrier = threading.Barrier(2)

def billing():
    barrier.wait()
    req = urllib.request.Request(API,
        data=json.dumps({"action":"billing","order-id":ORDER_ID,
            "data":{"ccn":"4242424242424242","exp":"12/25","cvv":"123"}}).encode(),
        headers={"Content-Type":"application/json","authorization":TOKEN_B}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as r: results["billing"] = json.loads(r.read())
    except Exception as e: results["billing"] = {"error": str(e)}

def update():
    barrier.wait()
    req = urllib.request.Request(API,
        data=json.dumps({"action":"update","order-id":ORDER_ID,"items":{"1":5}}).encode(),
        headers={"Content-Type":"application/json","authorization":TOKEN_B}, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=15) as r: results["update"] = json.loads(r.read())
    except Exception as e: results["update"] = {"error": str(e)}

t1,t2 = threading.Thread(target=billing), threading.Thread(target=update)
t1.start(); t2.start(); t1.join(); t2.join()

print(f"   Billing: {json.dumps(results.get('billing'))}")
print(f"   Update : {json.dumps(results.get('update'))}")

update_blocked = (
    results.get("update", {}).get("status") == "err" or
    "error" in results.get("update", {}) or
    "ConditionalCheck" in str(results.get("update", {})) or
    results.get("update", {}).get("msg", "").lower().find("state") != -1
)
if update_blocked:
    print("   UPDATE WAS BLOCKED by locking mechanism")
PYVERIFY

echo ""
sleep 2
FINAL=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get\",\"order-id\":\"$VERIFY_ORDER\"}")

FINAL_QTY=$(echo "$FINAL" | jq -r '.order.items["1"] // "unknown"')
FINAL_TOTAL=$(echo "$FINAL" | jq -r '.order.total // "unknown"')
FINAL_STATUS=$(echo "$FINAL" | jq -r '.order.status // "unknown"')

echo "   Final quantity : $FINAL_QTY"
echo "   Final total    : \$$FINAL_TOTAL"
echo "   Final status   : $FINAL_STATUS"

if [ "$FINAL_QTY" = "1" ]; then
    echo "   ✅ FIXED: Quantity remained 1 — race condition was blocked."
elif [ "$FINAL_QTY" = "5" ]; then
    echo "   ❌ Race condition still succeeds — fix not effective yet."
else
    echo "   ⚠️  Unexpected quantity '$FINAL_QTY' — check CloudWatch logs."
fi

echo ""
echo "[TEST 2] Normal sequential billing flow (should SUCCEED)..."

create_order_with_shipping "TOKEN_B" "verify8-legit-$(date +%s)" 1
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
LEGIT_STATUS=$(curl -s "$API" \
  -H "content-type: application/json" \
  -H "authorization: $TOKEN_B" \
  --data-raw "{\"action\":\"get\",\"order-id\":\"$LEGIT_ORDER\"}" | \
  jq -r '.order.status // "unknown"')

echo "   Order status after billing: $LEGIT_STATUS"

if [ "$LEGIT_STATUS" = "paid" ] || [ "$LEGIT_STATUS" = "complete" ]; then
    echo "   ✅ Legitimate billing flow still works correctly."
else
    echo "   ⚠️  Billing may not have completed — check Lambda logs."
fi

echo ""
echo "=========================================="
echo " Lesson 8 fix verification complete."
echo "=========================================="
