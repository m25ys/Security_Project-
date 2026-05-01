#!/bin/bash
# =============================================================
# SHARED HELPER: Create a new order and add shipping
# Usage: source helpers/create_order.sh <TOKEN> <CART_ID> <QTY>
#   Returns: ORDER_ID exported to caller's environment
# =============================================================
# Arguments:
#   $1 = JWT token variable name (e.g. TOKEN_B)
#   $2 = cart-id string (e.g. "lesson5-cart")
#   $3 = item quantity (default 1)
# =============================================================

create_order_with_shipping() {
    local TOKEN_VAR="$1"
    local CART_ID="${2:-helper-cart-001}"
    local QTY="${3:-1}"
    local TOKEN="${!TOKEN_VAR}"

    # Validate token
    if [ -z "$TOKEN" ] || [[ "$TOKEN" == PASTE* ]]; then
        echo "   ❌ Token '$TOKEN_VAR' is not set. Edit config.sh first."
        return 1
    fi

    # --- Step A: Create new order ---
    echo "   [create_order] Placing order (cart=$CART_ID, qty=$QTY)..."
    local NEW_ORDER
    NEW_ORDER=$(curl -s -X POST "$API" \
      -H "content-type: application/json" \
      -H "authorization: $TOKEN" \
      --data-raw "{
        \"action\": \"new\",
        \"cart-id\": \"$CART_ID\",
        \"items\": {\"1017\": $QTY}
      }")

    export ORDER_ID
    ORDER_ID=$(echo "$NEW_ORDER" | jq -r '."order-id" // .order_id // empty' 2>/dev/null)

    if [ -z "$ORDER_ID" ]; then
        echo "   ⚠️  Could not auto-create order. Response: $NEW_ORDER"
        echo "   Enter order-id manually (or press ENTER to abort):"
        read -r ORDER_ID
        [ -z "$ORDER_ID" ] && return 1
    fi
    echo "   [create_order] Order ID: $ORDER_ID"

    # --- Step B: Add shipping ---
    echo "   [create_order] Adding shipping..."
    local SHIP
    SHIP=$(curl -s -X POST "$API" \
      -H "content-type: application/json" \
      -H "authorization: $TOKEN" \
      --data-raw "{
        \"action\": \"shipping\",
        \"order-id\": \"$ORDER_ID\",
        \"data\": {
          \"address\": \"123 Test Street\",
          \"email\": \"testuser@dvsa.local\",
          \"name\": \"Test User\"
        }
      }")
    local SHIP_STATUS
    SHIP_STATUS=$(echo "$SHIP" | jq -r '.status // "unknown"' 2>/dev/null)
    echo "   [create_order] Shipping status: $SHIP_STATUS"
    return 0
}

# Guard: validate token is set (generic, call with token var name)
guard_token() {
    local VAR="$1"
    local VAL="${!VAR}"
    if [ -z "$VAL" ] || [[ "$VAL" == PASTE* ]]; then
        echo "❌ $VAR is not configured. Edit config.sh first."
        exit 1
    fi
}
