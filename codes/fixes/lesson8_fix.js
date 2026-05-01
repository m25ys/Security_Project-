// =============================================================
// LESSON 8 FIX: Prevent Race Condition with DynamoDB Locking
// Apply to: DVSA-ORDER-MANAGER Lambda (order-manager.js)
//           and DVSA-ADMIN-UPDATE-ORDERS Lambda
// =============================================================
//
// ROOT CAUSE:
//   The billing Lambda read the order (1 item), then wrote
//   "paid" status. Between the read and the write, a concurrent
//   update request could change the item quantity to 5.
//   The billing write used no condition — so it locked in the
//   "paid" status after the quantity had already been updated.
//   Result: 5 items for the price of 1.
//
// THE FIX:
//   1. When billing STARTS, atomically set a "billing_pending"
//      lock using a DynamoDB ConditionExpression.
//      This CAS (compare-and-swap) fails if the status has
//      already changed, preventing concurrent modifications.
//   2. Order update Lambda must reject modifications when
//      order status is "billing_pending" or "paid".
//   3. Billing completion uses a second conditional write that
//      only succeeds if status is still "billing_pending".
// =============================================================

// ================================================================
// PART A: Lock order at billing start (add to billing handler)
// ================================================================

/*
// ── Step 1: Atomically acquire the billing lock ──────────────
// This transition: "shipped" → "billing_pending"
// Uses ConditionExpression so only one billing attempt succeeds

const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

async function acquireBillingLock(orderId, expectedUserId) {
    try {
        await dynamodb.update({
            TableName: process.env.orders_table,
            Key: { 'order-id': orderId },
            UpdateExpression:    'SET #s = :pending',
            // Only lock if: current status is 'shipped' AND belongs to this user
            ConditionExpression: '#s = :shipped AND userId = :uid',
            ExpressionAttributeNames: {
                '#s': 'status'
            },
            ExpressionAttributeValues: {
                ':pending': 'billing_pending',
                ':shipped': 'shipped',
                ':uid':     expectedUserId
            }
        }).promise();
        return true;   // lock acquired
    } catch (e) {
        if (e.code === 'ConditionalCheckFailedException') {
            return false;  // order not in expected state — reject billing
        }
        throw e;
    }
}

// ── Step 2: Complete billing (transition: billing_pending → paid)
async function completeBilling(orderId, chargedTotal) {
    try {
        await dynamodb.update({
            TableName: process.env.orders_table,
            Key: { 'order-id': orderId },
            UpdateExpression:    'SET #s = :paid, chargedTotal = :total',
            // Only complete if still in billing_pending (not tampered with)
            ConditionExpression: '#s = :pending',
            ExpressionAttributeNames: {
                '#s': 'status'
            },
            ExpressionAttributeValues: {
                ':paid':    'paid',
                ':pending': 'billing_pending',
                ':total':   chargedTotal
            }
        }).promise();
        return true;
    } catch (e) {
        if (e.code === 'ConditionalCheckFailedException') {
            // Order state was tampered with during billing — abort
            console.error('Billing aborted: order state changed during payment processing');
            return false;
        }
        throw e;
    }
}

// ── Usage in billing action handler: ─────────────────────────
async function handleBilling(orderId, userId, paymentData, callback) {

    // 1. Acquire lock — prevents concurrent updates during payment
    const locked = await acquireBillingLock(orderId, userId);
    if (!locked) {
        return callback(null, resp(409, {
            status: 'err',
            msg: 'order is not in a billable state'
        }));
    }

    // 2. Read the LOCKED order to get the canonical item count and total
    //    (quantity is now frozen — any concurrent update will be rejected)
    const orderResult = await dynamodb.get({
        TableName: process.env.orders_table,
        Key: { 'order-id': orderId }
    }).promise();
    const order = orderResult.Item;
    const canonicalTotal = order.total;   // total at time of locking

    // 3. Process payment with the canonical total
    const paymentOk = await chargeCard(paymentData, canonicalTotal);
    if (!paymentOk) {
        // Release lock on payment failure: billing_pending → shipped
        await dynamodb.update({
            TableName: process.env.orders_table,
            Key: { 'order-id': orderId },
            UpdateExpression: 'SET #s = :shipped',
            ConditionExpression: '#s = :pending',
            ExpressionAttributeNames: { '#s': 'status' },
            ExpressionAttributeValues: {
                ':shipped': 'shipped',
                ':pending': 'billing_pending'
            }
        }).promise().catch(() => {});  // best-effort unlock
        return callback(null, resp(402, { status: 'err', msg: 'payment failed' }));
    }

    // 4. Mark paid — conditional write ensures no tampering occurred
    const completed = await completeBilling(orderId, canonicalTotal);
    if (!completed) {
        return callback(null, resp(409, {
            status: 'err',
            msg: 'billing integrity check failed — please retry'
        }));
    }

    return callback(null, resp(200, { status: 'ok', total: canonicalTotal }));
}
*/

// ================================================================
// PART B: Reject order updates when locked (add to update handler)
// ================================================================

/*
// Add this check BEFORE processing any order update:

const LOCKED_STATUSES = ['billing_pending', 'paid'];

async function handleUpdate(orderId, userId, newItems, callback) {

    // Fetch current order
    const result = await dynamodb.get({
        TableName: process.env.orders_table,
        Key: { 'order-id': orderId }
    }).promise();

    const order = result.Item;
    if (!order) {
        return callback(null, resp(404, { status: 'err', msg: 'order not found' }));
    }

    // ── RACE CONDITION FIX: reject update if order is locked ──
    if (LOCKED_STATUSES.includes(order.status)) {
        return callback(null, resp(409, {
            status: 'err',
            msg: `order cannot be modified in '${order.status}' state`
        }));
    }

    // Only the order owner can update
    if (order.userId !== userId) {
        return callback(null, resp(403, { status: 'err', msg: 'access denied' }));
    }

    // Use conditional write to prevent TOCTOU between check and write
    try {
        await dynamodb.update({
            TableName: process.env.orders_table,
            Key: { 'order-id': orderId },
            UpdateExpression: 'SET #items = :items, #total = :total',
            // Only update if status hasn't changed since we read it
            ConditionExpression: '#s NOT IN (:pending, :paid)',
            ExpressionAttributeNames: {
                '#items': 'items',
                '#total': 'total',
                '#s':     'status'
            },
            ExpressionAttributeValues: {
                ':items':   newItems,
                ':total':   calculateTotal(newItems),
                ':pending': 'billing_pending',
                ':paid':    'paid'
            }
        }).promise();
    } catch (e) {
        if (e.code === 'ConditionalCheckFailedException') {
            return callback(null, resp(409, {
                status: 'err',
                msg: 'order was modified concurrently — please retry'
            }));
        }
        throw e;
    }

    return callback(null, resp(200, { status: 'ok' }));
}
*/

console.log("Lesson 8 fix documentation — apply changes manually in Lambda console.");
