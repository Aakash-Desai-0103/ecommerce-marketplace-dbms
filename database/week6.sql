USE ecommerce_marketplace;

DROP PROCEDURE IF EXISTS place_marketplace_order;

DELIMITER $$

CREATE PROCEDURE place_marketplace_order(
    IN p_user_id BIGINT UNSIGNED,
    IN p_shipping_address_id BIGINT UNSIGNED,
    IN p_variant_id BIGINT UNSIGNED,
    IN p_quantity INT UNSIGNED,
    IN p_payment_method VARCHAR(20)
)
main: BEGIN
    DECLARE v_inventory_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_stock INT UNSIGNED DEFAULT NULL;
    DECLARE v_unit_price DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_total DECIMAL(10,2) DEFAULT NULL;
    DECLARE v_order_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_not_found BOOLEAN DEFAULT FALSE;
    DECLARE v_address_count INT DEFAULT 0;
    
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_not_found = TRUE;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    IF p_quantity IS NULL OR p_quantity = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order quantity must be greater than zero.';
    END IF;

    IF p_payment_method IS NULL OR p_payment_method NOT IN
       ('CARD', 'UPI', 'NET_BANKING', 'COD') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid payment method.';
    END IF;

    START TRANSACTION;

    -- The address must belong to the user placing the order.
    SELECT COUNT(*)
      INTO v_address_count
    FROM address
    WHERE address_id = p_shipping_address_id
      AND user_id = p_user_id;

    IF v_address_count = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Shipping address does not belong to this user.';
    END IF;

    -- Lock the stock row and read the current price for an active product.
    SET v_not_found = FALSE;

    SELECT i.inventory_id, i.quantity, pv.price
      INTO v_inventory_id, v_stock, v_unit_price
    FROM inventory AS i
    JOIN product_variant AS pv ON pv.variant_id = i.variant_id
    JOIN product AS pr ON pr.product_id = pv.product_id
    WHERE i.variant_id = p_variant_id
      AND pr.status = 'ACTIVE'
    FOR UPDATE;

    IF v_not_found OR v_inventory_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Active product variant or inventory record not found.';
    END IF;

    IF v_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient inventory; order was not placed.';
    END IF;

    SET v_total = v_unit_price * p_quantity;

    -- Create the order header.
    INSERT INTO orders (
        user_id, shipping_address_id, order_date, status, total_amount
    )
    VALUES (
        p_user_id, p_shipping_address_id, CURRENT_TIMESTAMP, 'PENDING', v_total
    );

    SET v_order_id = LAST_INSERT_ID();

    -- Store the unit price at purchase time rather than relying on future price.
    INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
    VALUES (v_order_id, p_variant_id, p_quantity, v_unit_price);

    -- This creates a payment record only; it does not charge a card or UPI.
    INSERT INTO payment (
        order_id, amount, payment_method, payment_status, paid_at
    )
    VALUES (
        v_order_id, v_total, p_payment_method, 'PENDING', NULL
    );

    -- Defensive guarded update: do not permit stock to be reduced below zero.
    UPDATE inventory
    SET quantity = quantity - p_quantity
    WHERE inventory_id = v_inventory_id
      AND quantity >= p_quantity;

    IF ROW_COUNT() <> 1 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Inventory changed or stock is insufficient; order rolled back.';
    END IF;

    -- Record the inventory movement. PURCHASE is represented as a negative
    -- quantity in this project's inventory_transaction table.
    INSERT INTO inventory_transaction (
        inventory_id, transaction_type, quantity, reference_type, reference_id
    )
    VALUES (
        v_inventory_id, 'PURCHASE', -p_quantity, 'ORDER', v_order_id
    );

   -- Record the initial status for the order's audit trail.
    INSERT INTO order_status_history (
        order_id, old_status, new_status, changed_at
    )
    VALUES (
        v_order_id, NULL, 'PENDING', CURRENT_TIMESTAMP
    );

    COMMIT;

    -- Return a useful confirmation row after successful COMMIT.
    SELECT
        v_order_id AS order_id,
        p_user_id AS user_id,
        p_variant_id AS variant_id,
        p_quantity AS quantity,
        v_unit_price AS unit_price,
        v_total AS total_amount,
        'PENDING' AS order_status,
        'PENDING' AS payment_status,
        'COMMITTED' AS transaction_result;
END$$

DELIMITER ;

-- ---------------------------------------------------------------------------
-- 2. HOW TO TEST THE ORDER TRANSACTION
-- ---------------------------------------------------------------------------
SELECT user_id, name, role
FROM users
WHERE role = 'CUSTOMER'
ORDER BY user_id
LIMIT 10;

SELECT address_id, user_id, city, state, postal_code
FROM address
ORDER BY address_id
LIMIT 20;

SELECT
    pv.variant_id,
    pv.sku,
    pv.price,
    pr.product_id,
    pr.name AS product_name,
    pr.status AS product_status,
    i.inventory_id,
    i.quantity AS available_stock
FROM product_variant AS pv
JOIN product AS pr ON pr.product_id = pv.product_id
JOIN inventory AS i ON i.variant_id = pv.variant_id
WHERE pr.status = 'ACTIVE'
ORDER BY pv.variant_id
LIMIT 30;

/*
After selecting a real CUSTOMER user_id, one of that user's address_id values,
and an active variant_id with enough inventory, run a call like this in MySQL.
Replace every example value with a valid ID from the queries above.

CALL place_marketplace_order(
    12,       -- p_user_id: valid customer user_id
    4,        -- p_shipping_address_id: address owned by that customer
    7,        -- p_variant_id: active variant with an inventory row
    2,        -- p_quantity
    'UPI'     -- CARD, UPI, NET_BANKING, or COD
);

If successful, the procedure commits the order and returns the order ID.
If validation fails or SQL raises an exception, the procedure rolls back and
returns an error. Check the result before running the same CALL again, because
a successful call creates a real order and reduces inventory.
*/


-- ---------------------------------------------------------------------------
-- 3. VERIFY THE RESULT OF A SUCCESSFUL ORDER
-- Replace 123 with the order_id returned by the procedure.
-- ---------------------------------------------------------------------------
-- SET @verify_order_id = 123;
--
-- SELECT o.order_id, o.user_id, o.shipping_address_id, o.status,
--        o.total_amount, o.order_date,
--        oi.variant_id, oi.quantity, oi.unit_price,
--        pay.payment_method, pay.payment_status, pay.amount
-- FROM orders AS o
-- JOIN order_item AS oi ON oi.order_id = o.order_id
-- LEFT JOIN payment AS pay ON pay.order_id = o.order_id
-- WHERE o.order_id = @verify_order_id;
--
-- SELECT it.transaction_id, it.inventory_id, it.transaction_type,
--        it.quantity, it.reference_type, it.reference_id, it.created_at
-- FROM inventory_transaction AS it
-- WHERE it.reference_type = 'ORDER'
--   AND it.reference_id = @verify_order_id;
--
-- SELECT *
-- FROM order_status_history
-- WHERE order_id = @verify_order_id
-- ORDER BY changed_at, history_id;


-- ---------------------------------------------------------------------------
-- 4. ATOMICITY: EXPLICIT ROLLBACK DEMONSTRATION
-- This test changes inventory inside a transaction, then rolls it back.
-- Use a valid inventory_id. Do not COMMIT this test.
-- ---------------------------------------------------------------------------
-- SET @test_inventory_id = 1;
--
-- SELECT inventory_id, quantity AS quantity_before
-- FROM inventory
-- WHERE inventory_id = @test_inventory_id;
--
-- START TRANSACTION;
--
-- SELECT inventory_id, quantity
-- FROM inventory
-- WHERE inventory_id = @test_inventory_id
-- FOR UPDATE;
--
-- UPDATE inventory
-- SET quantity = quantity + 5
-- WHERE inventory_id = @test_inventory_id;
--
-- SELECT inventory_id, quantity AS quantity_inside_transaction
-- FROM inventory
-- WHERE inventory_id = @test_inventory_id;
--
-- ROLLBACK;
--
-- SELECT inventory_id, quantity AS quantity_after_rollback
-- FROM inventory
-- WHERE inventory_id = @test_inventory_id;
--
-- Expected: quantity_after_rollback equals quantity_before.

-- ---------------------------------------------------------------------------
-- 5. CONSISTENCY: AUDIT EXISTING DATA
-- The supplied schema already defines CHECK constraints for order totals,
-- order-item quantity and price, variant price, payment amount, etc.
-- These queries look for common cross-table inconsistencies.
-- ---------------------------------------------------------------------------

-- Inventory should not be negative.
SELECT inventory_id, variant_id, quantity
FROM inventory
WHERE quantity < 0;

-- Order totals should match the sum of their order items.
-- This can identify historical/manual inserts that bypassed order processing.
SELECT
    o.order_id,
    o.total_amount,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS calculated_total
FROM orders AS o
LEFT JOIN order_item AS oi ON oi.order_id = o.order_id
GROUP BY o.order_id, o.total_amount
HAVING ABS(o.total_amount - COALESCE(SUM(oi.quantity * oi.unit_price), 0)) > 0.01;

-- Find inventory transaction records referring to orders that do not exist.
SELECT it.transaction_id, it.reference_id
FROM inventory_transaction AS it
LEFT JOIN orders AS o
  ON it.reference_type = 'ORDER'
 AND it.reference_id = o.order_id
WHERE it.reference_type = 'ORDER'
  AND o.order_id IS NULL;

-- Find inventory records whose quantity is at or below the reorder level.
SELECT inventory_id, variant_id, quantity, reorder_level
FROM inventory
WHERE quantity <= reorder_level
ORDER BY quantity, inventory_id;


-- ---------------------------------------------------------------------------
-- 6. ISOLATION DEMONSTRATION: TWO SESSIONS REQUIRED
-- Do not run the two-session experiment as one uninterrupted script.
-- Use two separate MySQL Workbench query tabs/connections or two mysql clients.
-- ---------------------------------------------------------------------------

/*
REPEATABLE READ (SESSION A)
--------------------------------
SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
START TRANSACTION;
SELECT quantity FROM inventory WHERE variant_id = 7;
-- Pause. In Session B, update that inventory row and COMMIT.
SELECT quantity FROM inventory WHERE variant_id = 7;
-- A normal consistent read should continue to see Session A's snapshot.
COMMIT;

SESSION B (while Session A is still open)
-----------------------------------------
START TRANSACTION;
UPDATE inventory SET quantity = quantity - 1 WHERE variant_id = 7;
COMMIT;

Use a valid variant_id and ensure stock is sufficient. Restore test data only
if you deliberately changed it and understand the impact.
*/

/*
READ COMMITTED (repeat the experiment with a fresh transaction)
--------------------------------
SESSION A:
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
START TRANSACTION;
SELECT quantity FROM inventory WHERE variant_id = 7;
-- After Session B commits an update:
SELECT quantity FROM inventory WHERE variant_id = 7;
COMMIT;

Under READ COMMITTED, the second ordinary SELECT can see a newly committed
value. Exact observations depend on when each statement executes.
*/


-- ---------------------------------------------------------------------------
-- 7. DURABILITY CHECK
-- After a successful procedure call, open a NEW connection/session and query
-- the committed order ID. The row should remain available.
-- ---------------------------------------------------------------------------
-- SELECT * FROM orders WHERE order_id = 123;
-- SELECT * FROM order_item WHERE order_id = 123;
-- SELECT * FROM payment WHERE order_id = 123;
-- SELECT * FROM inventory_transaction
-- WHERE reference_type = 'ORDER' AND reference_id = 123;


-- ---------------------------------------------------------------------------
-- 8. OPTIONAL: inspect the stored procedure definition
-- ---------------------------------------------------------------------------
-- SHOW CREATE PROCEDURE place_marketplace_order;