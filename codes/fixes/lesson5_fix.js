// =============================================================
// LESSON 5 FIX: Enforce Authorization on Admin Order Update
// Apply to: DVSA-ORDER-MANAGER Lambda (order-manager.js)
//           and DVSA-ADMIN-UPDATE-ORDERS Lambda
// =============================================================
//
// ROOT CAUSE:
//   The billing flow internally invoked DVSA-ADMIN-UPDATE-ORDERS
//   to change the order status. This invocation was reachable
//   from the normal billing API path without verifying that
//   the caller had actually completed a real payment step.
//   Additionally, the admin update Lambda accepted any caller
//   without checking if the invocation came from the authorized
//   billing Lambda.
//
// THE FIX (two-layer):
//   Layer 1 — ORDER-MANAGER: validate order state transitions
//             before invoking the admin update function.
//   Layer 2 — ADMIN-UPDATE-ORDERS: reject invocations that do
//             not originate from the trusted billing Lambda.
// =============================================================

// -------------------------------------------------------
// LAYER 1: Order state machine validation
// Add to order-manager.js BEFORE invoking admin update
// -------------------------------------------------------

// Valid state transitions — only these paths are allowed
const VALID_TRANSITIONS = {
    'new':      ['shipped'],
    'shipped':  ['billing_pending'],
    'billing_pending': ['paid'],
    'paid':     []           // terminal state — no further changes
};

/**
 * validateStateTransition: throws if the transition is invalid.
 * Call this BEFORE invoking DVSA-ADMIN-UPDATE-ORDERS.
 */
function validateStateTransition(currentStatus, targetStatus) {
    const allowed = VALID_TRANSITIONS[currentStatus] || [];
    if (!allowed.includes(targetStatus)) {
        throw new Error(
            `Invalid state transition: ${currentStatus} → ${targetStatus}. ` +
            `Allowed transitions: ${allowed.join(', ') || 'none (terminal state)'}`
        );
    }
}

// ── Usage in billing handler (add before Lambda invoke): ──
/*
// 1. Fetch current order state from DynamoDB
const order = await dynamodb.get({
    TableName: ORDERS_TABLE,
    Key: { 'order-id': orderId }
}).promise();

if (!order.Item) {
    return callback(null, resp(404, { status: 'err', msg: 'order not found' }));
}

// 2. Validate the state transition
try {
    validateStateTransition(order.Item.status, 'paid');
} catch (e) {
    console.log('Invalid state transition attempt:', e.message);
    return callback(null, resp(400, { status: 'err', msg: 'invalid order state for billing' }));
}

// 3. Verify billing actually succeeded (check payment processor response)
if (!paymentSucceeded) {
    return callback(null, resp(402, { status: 'err', msg: 'payment failed' }));
}

// ONLY THEN invoke the admin update:
await lambda.invoke({ FunctionName: 'DVSA-ADMIN-UPDATE-ORDERS', ... }).promise();
*/

// -------------------------------------------------------
// LAYER 2: DVSA-ADMIN-UPDATE-ORDERS — restrict caller
// Add to the admin update Lambda's handler
// -------------------------------------------------------

/*
exports.handler = async (event, context) => {

    // ── AUTHORIZATION CHECK ──────────────────────────────────
    // The admin update function should ONLY be invoked by the
    // trusted billing Lambda, not by any API Gateway request.
    //
    // When Lambda invokes Lambda, the invoking function's ARN
    // appears in context.invokedFunctionArn and the event source
    // is a direct invocation (not API Gateway).
    //
    // Check 1: must be a direct Lambda invocation, not API GW
    if (event.requestContext) {
        // event.requestContext exists only in API Gateway events
        console.log('BLOCKED: Admin update called directly from API Gateway');
        return {
            statusCode: 403,
            body: JSON.stringify({ status: 'err', msg: 'forbidden' })
        };
    }

    // Check 2: caller identity must be the billing Lambda
    const TRUSTED_BILLING_ARN = process.env.BILLING_LAMBDA_ARN;
    const callerArn = event._callerArn || '';   // set by billing Lambda

    if (TRUSTED_BILLING_ARN && callerArn !== TRUSTED_BILLING_ARN) {
        console.log(`BLOCKED: Untrusted caller ${callerArn}`);
        return { statusCode: 403, body: JSON.stringify({ status: 'err', msg: 'forbidden' }) };
    }

    // Check 3: validate the requested target status
    const ALLOWED_TARGET_STATUSES = ['paid', 'shipped', 'cancelled'];
    const targetStatus = event.status || event.newStatus;

    if (!targetStatus || !ALLOWED_TARGET_STATUSES.includes(targetStatus)) {
        return { statusCode: 400, body: JSON.stringify({ status: 'err', msg: 'invalid status' }) };
    }

    // ── CONDITIONAL UPDATE in DynamoDB ──────────────────────
    // Use a ConditionExpression so concurrent billing attempts
    // cannot cause race conditions (addresses Lesson 8 too).
    try {
        await dynamodb.update({
            TableName: ORDERS_TABLE,
            Key: { 'order-id': event['order-id'] },
            UpdateExpression: 'SET #s = :newStatus',
            // Only update if status has NOT already changed to paid
            ConditionExpression: '#s <> :alreadyPaid',
            ExpressionAttributeNames:  { '#s': 'status' },
            ExpressionAttributeValues: {
                ':newStatus':   targetStatus,
                ':alreadyPaid': 'paid'
            }
        }).promise();
    } catch (e) {
        if (e.code === 'ConditionalCheckFailedException') {
            return { statusCode: 409, body: JSON.stringify({ status: 'err', msg: 'order already processed' }) };
        }
        throw e;
    }

    return { statusCode: 200, body: JSON.stringify({ status: 'ok' }) };
};
*/

console.log("Lesson 5 fix documentation — apply changes manually in Lambda console.");
