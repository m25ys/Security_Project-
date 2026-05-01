// =============================================================
// LESSON 10 FIX: Centralized Safe Error Handler
// Apply this pattern to all Lambda functions in DVSA
// =============================================================
//
// HOW TO APPLY:
// 1. Go to AWS Console → Lambda → DVSA-ORDER-MANAGER
// 2. Open order-manager.js
// 3. Add the safeError helper function below
// 4. Replace all direct callback(err) / throw patterns
// 5. Click Deploy
// =============================================================

// -------------------------------------------------------
// ADD this helper at the TOP of each Lambda handler file:
// -------------------------------------------------------

/**
 * safeError: Returns a generic client-safe error response
 * while logging full details internally to CloudWatch only.
 */
function safeError(callback, internalError, clientMessage, statusCode) {
    // Log full details INTERNALLY (CloudWatch only)
    console.error("INTERNAL_ERROR:", {
        message: internalError.message || internalError,
        stack: internalError.stack || "no stack",
        timestamp: new Date().toISOString()
    });

    // Return GENERIC message to client (no stack trace, no paths)
    return callback(null, {
        statusCode: statusCode || 500,
        headers: { "Access-Control-Allow-Origin": "*" },
        body: JSON.stringify({
            status: "err",
            msg: clientMessage || "An error occurred. Please try again."
        })
    });
}

// -------------------------------------------------------
// INPUT VALIDATION helper - validate before processing:
// -------------------------------------------------------

function validateOrderRequest(body) {
    const errors = [];

    if (!body || typeof body !== 'object') {
        return { valid: false, error: "invalid request body" };
    }

    const ALLOWED_ACTIONS = ["new", "get", "orders", "shipping", "billing", "cancel"];

    if (!body.action || typeof body.action !== 'string') {
        errors.push("action is required and must be a string");
    } else if (!ALLOWED_ACTIONS.includes(body.action)) {
        errors.push("invalid action");
    }

    if (body["order-id"] && typeof body["order-id"] !== 'string') {
        errors.push("order-id must be a string");
    }

    if (body["order-id"] && !/^[a-zA-Z0-9\-]{0,64}$/.test(body["order-id"])) {
        errors.push("order-id contains invalid characters");
    }

    return errors.length === 0
        ? { valid: true }
        : { valid: false, error: errors.join(", ") };
}

// -------------------------------------------------------
// USAGE EXAMPLE - Replace vulnerable handler pattern:
// -------------------------------------------------------

/*
// BEFORE (VULNERABLE - exposes stack traces):
exports.handler = function(event, context, callback) {
    var body = JSON.parse(event.body);  // throws if malformed
    var action = body.action;
    // ... if action is undefined, crashes with unhelpful error
    doSomething(body).then(result => callback(null, result));
    // .catch is missing - unhandled rejection leaks internals
};


// AFTER (FIXED - safe error handling):
exports.handler = function(event, context, callback) {

    // 1. Parse body safely
    var body;
    try {
        body = JSON.parse(event.body || "{}");
    } catch (e) {
        return callback(null, {
            statusCode: 400,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ status: "err", msg: "invalid request format" })
        });
    }

    // 2. Validate input before processing
    var validation = validateOrderRequest(body);
    if (!validation.valid) {
        return callback(null, {
            statusCode: 400,
            headers: { "Access-Control-Allow-Origin": "*" },
            body: JSON.stringify({ status: "err", msg: validation.error })
        });
    }

    // 3. Process with centralized error catching
    processRequest(body)
        .then(result => callback(null, result))
        .catch(err => safeError(callback, err, "Request processing failed"));
};
*/

console.log("This file is documentation only - apply changes manually in AWS Console.");
