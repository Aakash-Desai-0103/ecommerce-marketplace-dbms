USE ecommerce_marketplace;

-- ============================================================
-- WEEK 6 — TRANSACTIONS AND ACID PROPERTIES
-- Run after week3_database_objects.sql: stock is checked and
-- deducted by the Week 3 order_item triggers, inside this
-- procedure's transaction, so a ROLLBACK undoes them too.
-- ============================================================

-- ---------------------------------------------------------------------------
-- 1. ORDER PLACEMENT AS ONE ATOMIC TRANSACTION
-- ---------------------------------------------------------------------------

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
    -- Week 3 triggers fire here: trg_check_stock_before_order_item re-checks
    -- stock, trg_reduce_inventory deducts it and writes the PURCHASE row to
    -- inventory_transaction. Both run inside this transaction.
    INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
    VALUES (v_order_id, p_variant_id, p_quantity, v_unit_price);

    -- This creates a payment record only; it does not charge a card or UPI.
    INSERT INTO payment (
        order_id, amount, payment_method, payment_status, paid_at
    )
    VALUES (
        v_order_id, v_total, p_payment_method, 'PENDING', NULL
    );

    -- Inventory is NOT updated here: trg_reduce_inventory has already done it.
    -- (Doing it in both places deducted the stock twice.)

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


-- ---------------------------------------------------------------------------
-- 3. LIVE DEMONSTRATION: COMMIT vs ROLLBACK (visible step by step)
-- Run as-is. Each block prints the value before, inside and after the
-- transaction, plus a PASS/FAIL verdict.
-- ---------------------------------------------------------------------------

-- 3.1 ROLLBACK: a change made inside a transaction is undone
SELECT quantity INTO @rb_before FROM inventory WHERE inventory_id = 1;

START TRANSACTION;
UPDATE inventory SET quantity = quantity + 5 WHERE inventory_id = 1;
SELECT @rb_before AS quantity_before, quantity AS quantity_inside_transaction
FROM inventory WHERE inventory_id = 1;
ROLLBACK;

SELECT @rb_before AS quantity_before,
       quantity   AS quantity_after_rollback,
       IF(quantity = @rb_before, 'PASS - change undone', 'FAIL') AS rollback_result
FROM inventory WHERE inventory_id = 1;


-- 3.2 COMMIT: a committed change is permanent (a later ROLLBACK cannot undo it)
SELECT reorder_level INTO @cm_before FROM inventory WHERE inventory_id = 2;

START TRANSACTION;
UPDATE inventory SET reorder_level = reorder_level + 1 WHERE inventory_id = 2;
COMMIT;
ROLLBACK;   -- has nothing to undo: the change was already committed

SELECT @cm_before    AS reorder_level_before,
       reorder_level AS reorder_level_after_commit,
       IF(reorder_level = @cm_before + 1, 'PASS - change persisted', 'FAIL') AS commit_result
FROM inventory WHERE inventory_id = 2;

-- Put the demo value back (also committed)
UPDATE inventory SET reorder_level = @cm_before WHERE inventory_id = 2;


-- 3.3 ROW LOCKING: SELECT ... FOR UPDATE places an exclusive (X) lock on the
-- inventory row; the lock is held until COMMIT / ROLLBACK and then released.
-- performance_schema.data_locks shows the locks held by THIS session.
START TRANSACTION;

SELECT inventory_id, variant_id, quantity
FROM inventory
WHERE variant_id = 7
FOR UPDATE;

SELECT object_name AS locked_table, index_name, lock_type, lock_mode, lock_status, lock_data
FROM performance_schema.data_locks
WHERE thread_id = PS_CURRENT_THREAD_ID()
  AND object_schema = 'ecommerce_marketplace'
  AND object_name = 'inventory';

COMMIT;

SELECT COUNT(*) AS inventory_locks_after_commit,
       IF(COUNT(*) = 0, 'PASS - lock released on COMMIT', 'FAIL') AS lock_release_result
FROM performance_schema.data_locks
WHERE thread_id = PS_CURRENT_THREAD_ID()
  AND object_schema = 'ecommerce_marketplace'
  AND object_name = 'inventory';


-- ---------------------------------------------------------------------------
-- 4. AUTOMATED ACID TEST SUITE
-- Calls place_marketplace_order on valid and invalid input, forces failures
-- in the middle of a transaction, and checks the database after each case.
-- Results are collected in a table and printed at the end.
--
-- NOTE: test A1 places one REAL order (Diya, 1 x Air Max 270 size 9) and
-- commits it; it is kept so durability can be checked from a new session
-- (section 6). Every other test leaves the data unchanged.
-- ---------------------------------------------------------------------------

DROP TEMPORARY TABLE IF EXISTS acid_test_results;
CREATE TEMPORARY TABLE acid_test_results (
    test_no   VARCHAR(5),
    property  VARCHAR(20),
    test_case VARCHAR(120),
    expected  VARCHAR(150),
    actual    VARCHAR(255),
    result    VARCHAR(4)
);

DROP PROCEDURE IF EXISTS sp_week6_acid_tests;

DELIMITER $$

CREATE PROCEDURE sp_week6_acid_tests()
BEGIN
    DECLARE v_err          VARCHAR(255) DEFAULT NULL;
    DECLARE v_err_no       INT DEFAULT NULL;
    DECLARE v_orders_0     INT;
    DECLARE v_orders_1     INT;
    DECLARE v_orders_mid   INT;
    DECLARE v_items_0      INT;
    DECLARE v_items_1      INT;
    DECLARE v_pay_0        INT;
    DECLARE v_pay_1        INT;
    DECLARE v_ledger_0     INT;
    DECLARE v_ledger_1     INT;
    DECLARE v_stock_0      INT;
    DECLARE v_stock_1      INT;
    DECLARE v_new_order    BIGINT UNSIGNED;
    DECLARE v_total        DECIMAL(10,2);
    DECLARE v_pay_amount   DECIMAL(10,2);
    DECLARE v_hist         INT;
    DECLARE v_led_qty      INT;
    DECLARE v_locks        INT;
    DECLARE v_lock_mode    VARCHAR(100);
    DECLARE v_price_0      DECIMAL(10,2);
    DECLARE v_price_1      DECIMAL(10,2);
    DECLARE v_bad_totals   INT;
    DECLARE v_bad_pay      INT;
    DECLARE v_bad_ledger   INT;
    DECLARE v_inside       INT;

    -- Any error raised by a test is captured here instead of stopping the suite
    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT, v_err_no = MYSQL_ERRNO;
    END;

    -- =====================================================================
    -- A1  COMMIT: a valid order is committed with ALL of its parts
    -- =====================================================================
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SELECT COUNT(*) INTO v_items_0  FROM order_item;
    SELECT COUNT(*) INTO v_pay_0    FROM payment;
    SELECT COUNT(*) INTO v_ledger_0 FROM inventory_transaction;
    SELECT quantity INTO v_stock_0  FROM inventory WHERE variant_id = 7;
    SET v_err = NULL;

    CALL place_marketplace_order(2, 3, 7, 1, 'UPI');

    SELECT MAX(order_id) INTO v_new_order FROM orders WHERE user_id = 2;
    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    SELECT COUNT(*) INTO v_items_1  FROM order_item;
    SELECT COUNT(*) INTO v_pay_1    FROM payment;
    SELECT COUNT(*) INTO v_ledger_1 FROM inventory_transaction;
    SELECT quantity INTO v_stock_1  FROM inventory WHERE variant_id = 7;
    SELECT total_amount INTO v_total FROM orders WHERE order_id = v_new_order;
    SELECT amount INTO v_pay_amount FROM payment WHERE order_id = v_new_order;
    SELECT COUNT(*) INTO v_hist FROM order_status_history WHERE order_id = v_new_order;
    SELECT SUM(quantity) INTO v_led_qty FROM inventory_transaction
     WHERE reference_type = 'ORDER' AND reference_id = v_new_order;

    INSERT INTO acid_test_results VALUES
    ('A1', 'Atomicity/Commit', 'Valid order: CALL place_marketplace_order(2, 3, 7, 1, ''UPI'')',
     '+1 order, +1 item, +1 payment, +1 ledger row, stock -1, status history logged',
     CONCAT('order #', v_new_order, ': orders +', v_orders_1 - v_orders_0,
            ', items +', v_items_1 - v_items_0, ', payments +', v_pay_1 - v_pay_0,
            ', ledger +', v_ledger_1 - v_ledger_0, ' (qty ', IFNULL(v_led_qty, 0), ')',
            ', stock ', v_stock_0, '->', v_stock_1, ', history rows ', v_hist,
            IFNULL(CONCAT(', error: ', v_err), '')),
     IF(v_err IS NULL AND v_orders_1 = v_orders_0 + 1 AND v_items_1 = v_items_0 + 1
        AND v_pay_1 = v_pay_0 + 1 AND v_ledger_1 = v_ledger_0 + 1 AND v_led_qty = -1
        AND v_stock_1 = v_stock_0 - 1 AND v_hist = 1, 'PASS', 'FAIL'));

    INSERT INTO acid_test_results VALUES
    ('A2', 'Consistency', 'Committed order: payment amount = order total',
     'payment.amount = orders.total_amount',
     CONCAT('total ', v_total, ', payment ', v_pay_amount),
     IF(v_total = v_pay_amount, 'PASS', 'FAIL'));

    -- =====================================================================
    -- B1-B4  ROLLBACK: invalid orders are rejected and leave NO trace
    -- =====================================================================

    -- B1 insufficient stock (rejected after the FOR UPDATE row lock is taken)
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SELECT quantity INTO v_stock_0 FROM inventory WHERE variant_id = 10;
    SET v_err = NULL;
    CALL place_marketplace_order(2, 3, 10, 50, 'UPI');
    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    SELECT quantity INTO v_stock_1 FROM inventory WHERE variant_id = 10;
    INSERT INTO acid_test_results VALUES
    ('B1', 'Atomicity/Rollback', 'Order 50 KALLAX shelves (stock is low)',
     'Error raised; orders and stock unchanged',
     CONCAT('error: ', IFNULL(v_err, 'none'), ' | orders +', v_orders_1 - v_orders_0,
            ', stock ', v_stock_0, '->', v_stock_1),
     IF(v_err LIKE 'Insufficient inventory%' AND v_orders_1 = v_orders_0
        AND v_stock_1 = v_stock_0, 'PASS', 'FAIL'));

    -- B2 shipping address belongs to another user
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SET v_err = NULL;
    CALL place_marketplace_order(2, 1, 7, 1, 'UPI');
    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    INSERT INTO acid_test_results VALUES
    ('B2', 'Atomicity/Rollback', 'Order using address 1 (belongs to another user)',
     'Error raised; no order written',
     CONCAT('error: ', IFNULL(v_err, 'none'), ' | orders +', v_orders_1 - v_orders_0),
     IF(v_err LIKE 'Shipping address%' AND v_orders_1 = v_orders_0, 'PASS', 'FAIL'));

    -- B3 invalid payment method
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SET v_err = NULL;
    CALL place_marketplace_order(2, 3, 7, 1, 'CASH');
    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    INSERT INTO acid_test_results VALUES
    ('B3', 'Atomicity/Rollback', 'Order with payment method ''CASH''',
     'Error raised; no order written',
     CONCAT('error: ', IFNULL(v_err, 'none'), ' | orders +', v_orders_1 - v_orders_0),
     IF(v_err = 'Invalid payment method.' AND v_orders_1 = v_orders_0, 'PASS', 'FAIL'));

    -- B4 quantity of zero
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SET v_err = NULL;
    CALL place_marketplace_order(2, 3, 7, 0, 'UPI');
    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    INSERT INTO acid_test_results VALUES
    ('B4', 'Atomicity/Rollback', 'Order with quantity 0',
     'Error raised; no order written',
     CONCAT('error: ', IFNULL(v_err, 'none'), ' | orders +', v_orders_1 - v_orders_0),
     IF(v_err LIKE 'Order quantity%' AND v_orders_1 = v_orders_0, 'PASS', 'FAIL'));

    -- =====================================================================
    -- B5  ROLLBACK after PARTIAL work: the order header is written, then the
    --     order item fails. ROLLBACK must remove the header as well.
    -- =====================================================================
    SELECT COUNT(*) INTO v_orders_0 FROM orders;
    SET v_err = NULL, v_inside = NULL;

    partial_txn: BEGIN
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
            GET DIAGNOSTICS CONDITION 1 v_err = MESSAGE_TEXT;
            ROLLBACK;
        END;

        START TRANSACTION;

        INSERT INTO orders (user_id, shipping_address_id, status, total_amount)
        VALUES (2, 3, 'PENDING', 0);

        SELECT COUNT(*) INTO v_inside FROM orders;        -- header is visible here

        -- 999 units: the Week 3 BEFORE INSERT trigger rejects this line
        INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
        VALUES (LAST_INSERT_ID(), 10, 999, 6999.00);

        COMMIT;                                           -- never reached
    END partial_txn;

    SELECT COUNT(*) INTO v_orders_1 FROM orders;
    INSERT INTO acid_test_results VALUES
    ('B5', 'Atomicity/Rollback', 'Write order header, then fail on order item (999 units)',
     'Header visible inside txn; gone after ROLLBACK',
     CONCAT('orders before ', v_orders_0, ', inside txn ', IFNULL(v_inside, '?'),
            ', after rollback ', v_orders_1, ' | error: ', IFNULL(v_err, 'none')),
     IF(v_inside = v_orders_0 + 1 AND v_orders_1 = v_orders_0 AND v_err IS NOT NULL, 'PASS', 'FAIL'));

    -- =====================================================================
    -- C1-C2  ROW LOCKING with SELECT ... FOR UPDATE
    -- =====================================================================
    START TRANSACTION;
    SELECT quantity INTO v_stock_0 FROM inventory WHERE variant_id = 7 FOR UPDATE;

    SELECT COUNT(*), GROUP_CONCAT(DISTINCT lock_mode ORDER BY lock_mode SEPARATOR ' / ')
      INTO v_locks, v_lock_mode
    FROM performance_schema.data_locks
    WHERE thread_id = PS_CURRENT_THREAD_ID()
      AND object_schema = 'ecommerce_marketplace'
      AND object_name = 'inventory'
      AND lock_type = 'RECORD';
    COMMIT;

    INSERT INTO acid_test_results VALUES
    ('C1', 'Isolation/Locking', 'SELECT ... FOR UPDATE on inventory row of variant 7',
     'Exclusive (X) record lock held by this transaction',
     CONCAT(v_locks, ' record lock(s), mode: ', IFNULL(v_lock_mode, 'none')),
     IF(v_locks > 0 AND v_lock_mode LIKE '%X%', 'PASS', 'FAIL'));

    SELECT COUNT(*) INTO v_locks
    FROM performance_schema.data_locks
    WHERE thread_id = PS_CURRENT_THREAD_ID()
      AND object_schema = 'ecommerce_marketplace'
      AND object_name = 'inventory';

    INSERT INTO acid_test_results VALUES
    ('C2', 'Isolation/Locking', 'Locks after COMMIT',
     'All row locks released',
     CONCAT(v_locks, ' lock(s) remaining'),
     IF(v_locks = 0, 'PASS', 'FAIL'));

    INSERT INTO acid_test_results VALUES
    ('C3', 'Isolation', 'Session isolation level',
     'REPEATABLE-READ (InnoDB default)',
     @@transaction_isolation,
     IF(@@transaction_isolation = 'REPEATABLE-READ', 'PASS', 'FAIL'));

    -- =====================================================================
    -- S1-S2  SERIALIZABILITY: under SERIALIZABLE, even a plain SELECT takes
    --        shared (S) locks, so no other transaction can change the rows
    --        it has read (this is what makes every schedule serializable).
    --        Under REPEATABLE READ the same SELECT is a lock-free snapshot.
    -- =====================================================================
    SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    START TRANSACTION;
    SELECT quantity INTO v_stock_0 FROM inventory WHERE variant_id = 7;   -- plain read

    SELECT COUNT(*), GROUP_CONCAT(DISTINCT lock_mode ORDER BY lock_mode SEPARATOR ' / ')
      INTO v_locks, v_lock_mode
    FROM performance_schema.data_locks
    WHERE thread_id = PS_CURRENT_THREAD_ID()
      AND object_schema = 'ecommerce_marketplace'
      AND object_name = 'inventory'
      AND lock_type = 'RECORD';
    COMMIT;

    INSERT INTO acid_test_results VALUES
    ('S1', 'Serializability', 'SERIALIZABLE: plain SELECT on inventory row (no FOR UPDATE)',
     'Shared (S) record lock taken automatically',
     CONCAT(v_locks, ' record lock(s), mode: ', IFNULL(v_lock_mode, 'none')),
     IF(v_locks > 0 AND v_lock_mode LIKE 'S%', 'PASS', 'FAIL'));

    SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    START TRANSACTION;
    SELECT quantity INTO v_stock_0 FROM inventory WHERE variant_id = 7;   -- same plain read

    SELECT COUNT(*) INTO v_locks
    FROM performance_schema.data_locks
    WHERE thread_id = PS_CURRENT_THREAD_ID()
      AND object_schema = 'ecommerce_marketplace'
      AND object_name = 'inventory'
      AND lock_type = 'RECORD';
    COMMIT;

    INSERT INTO acid_test_results VALUES
    ('S2', 'Serializability', 'REPEATABLE READ: the same plain SELECT',
     'No lock (consistent snapshot read)',
     CONCAT(v_locks, ' record lock(s)'),
     IF(v_locks = 0, 'PASS', 'FAIL'));

    -- =====================================================================
    -- D1-D3  CONSISTENCY: constraints reject invalid data; data reconciles
    -- =====================================================================
    SELECT price INTO v_price_0 FROM product_variant WHERE variant_id = 1;
    SET v_err = NULL, v_err_no = NULL;
    UPDATE product_variant SET price = -1 WHERE variant_id = 1;
    SELECT price INTO v_price_1 FROM product_variant WHERE variant_id = 1;
    INSERT INTO acid_test_results VALUES
    ('D1', 'Consistency', 'UPDATE variant price to -1 (CHECK price >= 0)',
     'Rejected by CHECK constraint (error 3819); price unchanged',
     CONCAT('error ', IFNULL(v_err_no, '-'), ': ', IFNULL(v_err, 'none'),
            ' | price ', v_price_0, '->', v_price_1),
     IF(v_err_no = 3819 AND v_price_0 = v_price_1, 'PASS', 'FAIL'));

    SELECT COUNT(*) INTO v_items_0 FROM order_item;
    SET v_err = NULL, v_err_no = NULL;
    INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
    VALUES (999999, 1, 1, 100.00);
    SELECT COUNT(*) INTO v_items_1 FROM order_item;
    INSERT INTO acid_test_results VALUES
    ('D2', 'Consistency', 'Insert order item for non-existent order 999999',
     'Rejected by FOREIGN KEY (error 1452); nothing inserted',
     CONCAT('error ', IFNULL(v_err_no, '-'), ' | order items +', v_items_1 - v_items_0),
     IF(v_err_no = 1452 AND v_items_1 = v_items_0, 'PASS', 'FAIL'));

    SELECT COUNT(*) INTO v_bad_totals
    FROM orders o
    LEFT JOIN (SELECT order_id, SUM(quantity * unit_price) s FROM order_item GROUP BY order_id) i
           ON i.order_id = o.order_id
    LEFT JOIN (SELECT order_id, SUM(discount_amount) d FROM order_coupon GROUP BY order_id) c
           ON c.order_id = o.order_id
    WHERE ABS(o.total_amount - (COALESCE(i.s, 0) - COALESCE(c.d, 0))) > 0.01;

    SELECT COUNT(*) INTO v_bad_pay
    FROM orders o JOIN payment p ON p.order_id = o.order_id
    WHERE o.total_amount <> p.amount;

    SELECT COUNT(*) INTO v_bad_ledger
    FROM (SELECT i.inventory_id
          FROM inventory i
          LEFT JOIN inventory_transaction t ON t.inventory_id = i.inventory_id
          GROUP BY i.inventory_id, i.quantity
          HAVING i.quantity <> COALESCE(SUM(t.quantity), 0)) x;

    INSERT INTO acid_test_results VALUES
    ('D3', 'Consistency', 'Audit after all tests: totals, payments, stock ledger',
     '0 mismatches in each check',
     CONCAT(v_bad_totals, ' order-total, ', v_bad_pay, ' payment, ', v_bad_ledger, ' stock-ledger mismatches'),
     IF(v_bad_totals = 0 AND v_bad_pay = 0 AND v_bad_ledger = 0, 'PASS', 'FAIL'));

    -- =====================================================================
    -- E1  DURABILITY settings (full check from a new session: section 6)
    -- =====================================================================
    INSERT INTO acid_test_results VALUES
    ('E1', 'Durability', 'innodb_flush_log_at_trx_commit',
     '1 = redo log written and flushed to disk at every COMMIT',
     CAST(@@innodb_flush_log_at_trx_commit AS CHAR),
     IF(@@innodb_flush_log_at_trx_commit = 1, 'PASS', 'FAIL'));

    -- Remember the committed order for the durability check
    SET @durability_order_id = v_new_order;
END$$

DELIMITER ;

CALL sp_week6_acid_tests();

-- Test report
SELECT test_no, property, test_case, expected, actual, result
FROM acid_test_results
ORDER BY test_no;

SELECT COUNT(*) AS total_tests,
       SUM(result = 'PASS') AS passed,
       SUM(result = 'FAIL') AS failed
FROM acid_test_results;

SELECT @durability_order_id AS order_to_check_from_a_new_session;


-- ---------------------------------------------------------------------------
-- 5. CONSISTENCY: AUDIT EXISTING DATA (every query should return NO rows,
--    except the last one, which lists low-stock items)
-- ---------------------------------------------------------------------------

-- Inventory can never go negative: the column is INT UNSIGNED and the
-- Week 3 BEFORE INSERT trigger blocks over-ordering.
SELECT inventory_id, variant_id, quantity
FROM inventory
WHERE quantity < 0;

-- Order totals should equal item subtotal minus coupon discounts.
SELECT
    o.order_id,
    o.total_amount,
    COALESCE(items.subtotal, 0) - COALESCE(cpn.discount, 0) AS calculated_total
FROM orders AS o
LEFT JOIN (
    SELECT order_id, SUM(quantity * unit_price) AS subtotal
    FROM order_item
    GROUP BY order_id
) AS items ON items.order_id = o.order_id
LEFT JOIN (
    SELECT order_id, SUM(discount_amount) AS discount
    FROM order_coupon
    GROUP BY order_id
) AS cpn ON cpn.order_id = o.order_id
WHERE ABS(o.total_amount - (COALESCE(items.subtotal, 0) - COALESCE(cpn.discount, 0))) > 0.01;

-- Payment amount should equal the order total.
SELECT o.order_id, o.total_amount, p.amount AS payment_amount
FROM orders AS o
JOIN payment AS p ON p.order_id = o.order_id
WHERE o.total_amount <> p.amount;

-- Current stock should equal the sum of the stock ledger.
SELECT
    i.inventory_id,
    i.variant_id,
    i.quantity AS current_stock,
    COALESCE(SUM(it.quantity), 0) AS ledger_stock
FROM inventory AS i
LEFT JOIN inventory_transaction AS it ON it.inventory_id = i.inventory_id
GROUP BY i.inventory_id, i.variant_id, i.quantity
HAVING i.quantity <> COALESCE(SUM(it.quantity), 0);

-- Refunds should never exceed what was paid for the returned item.
SELECT r.refund_id, r.amount, oi.quantity * oi.unit_price AS item_value
FROM refund AS r
JOIN return_request AS rr ON rr.return_id = r.return_id
JOIN order_item AS oi ON oi.order_item_id = rr.order_item_id
WHERE r.amount > oi.quantity * oi.unit_price;

-- Inventory transaction records referring to orders that do not exist.
SELECT it.transaction_id, it.reference_id
FROM inventory_transaction AS it
LEFT JOIN orders AS o
  ON it.reference_type = 'ORDER'
 AND it.reference_id = o.order_id
WHERE it.reference_type = 'ORDER'
  AND o.order_id IS NULL;

-- Inventory at or below the reorder level (informational: lists items).
SELECT inventory_id, variant_id, quantity, reorder_level
FROM inventory
WHERE quantity <= reorder_level
ORDER BY quantity, inventory_id;


-- ---------------------------------------------------------------------------
-- 6. DURABILITY CHECK (manual, needs a NEW connection)
-- 1. Type  exit  to close this client.
-- 2. Reconnect:  mysql -u root -p ecommerce_marketplace
--    (for the strongest proof, restart the MySQL service first:
--     Windows admin cmd ->  net stop MySQL80  then  net start MySQL80)
-- 3. Run the query below. The order committed by test A1 must still exist,
--    with its item, payment and ledger row.
-- ---------------------------------------------------------------------------
/*
SELECT o.order_id, o.status, o.total_amount, oi.variant_id, oi.quantity,
       p.payment_method, p.amount, it.transaction_type, it.quantity AS stock_change
FROM orders o
JOIN order_item oi ON oi.order_id = o.order_id
JOIN payment p     ON p.order_id = o.order_id
JOIN inventory_transaction it
  ON it.reference_type = 'ORDER' AND it.reference_id = o.order_id
WHERE o.order_id = (SELECT MAX(order_id) FROM orders WHERE user_id = 2);
*/


-- ---------------------------------------------------------------------------
-- 7. ISOLATION: TWO-SESSION DEMONSTRATIONS (manual)
-- Open TWO mysql clients (Session A and Session B), both logged in and
-- running  USE ecommerce_marketplace;  Then run the steps in the order shown.
-- ---------------------------------------------------------------------------

/*
7.1 ROW LOCK BLOCKS A CONCURRENT WRITER (prevents overselling)
--------------------------------------------------------------
A:  START TRANSACTION;
A:  SELECT quantity FROM inventory WHERE variant_id = 7 FOR UPDATE;   -- A holds the lock

B:  SET SESSION innodb_lock_wait_timeout = 5;
B:  UPDATE inventory SET quantity = quantity - 1 WHERE variant_id = 7;
    -- B WAITS. After 5 seconds:
    -- ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction

A:  COMMIT;                                                           -- releases the lock
B:  (run nothing - the failed UPDATE changed nothing)

Variation: run B's UPDATE again but COMMIT in A within 5 seconds.
B's UPDATE then completes as soon as A commits. Restore afterwards:
B:  UPDATE inventory SET quantity = quantity + 1 WHERE variant_id = 7;


7.2 TWO CUSTOMERS BUY THE LAST UNIT AT THE SAME TIME
---------------------------------------------------
Variant 8 (Air Max 270, size 10) has very little stock. Both sessions call
the procedure at the same moment; FOR UPDATE makes the second one wait for
the first, then re-read the reduced stock. Stock never goes negative.

A:  SELECT quantity FROM inventory WHERE variant_id = 8;   -- note the value (N)
A:  CALL place_marketplace_order(1, 1, 8, <N>, 'UPI');     -- buys all N units
B:  CALL place_marketplace_order(2, 3, 8, 1, 'UPI');
    -- ERROR 1644: Insufficient inventory; order was not placed.


7.3 REPEATABLE READ: a transaction keeps seeing its own snapshot
----------------------------------------------------------------
A:  SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;
A:  START TRANSACTION;
A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;        -- e.g. 5

B:  UPDATE inventory SET reorder_level = reorder_level + 1 WHERE variant_id = 1;  -- autocommit

A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;        -- STILL 5 (snapshot)
A:  COMMIT;
A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;        -- now 6

B:  UPDATE inventory SET reorder_level = reorder_level - 1 WHERE variant_id = 1;  -- restore


7.4 READ COMMITTED: a transaction sees other sessions' new commits
------------------------------------------------------------------
A:  SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
A:  START TRANSACTION;
A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;        -- e.g. 5

B:  UPDATE inventory SET reorder_level = reorder_level + 1 WHERE variant_id = 1;

A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;        -- now 6 (non-repeatable read)
A:  COMMIT;
A:  SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;         -- back to default

B:  UPDATE inventory SET reorder_level = reorder_level - 1 WHERE variant_id = 1;  -- restore


7.5 LOST UPDATE (non-serializable schedule) and how locking prevents it
------------------------------------------------------------------------
Two clerks each sell 1 unit of variant 1 using read-then-write logic.

(a) WITHOUT a lock -> one sale is lost
A:  START TRANSACTION;
A:  SELECT quantity INTO @qa FROM inventory WHERE variant_id = 1;     -- reads 25
B:  START TRANSACTION;
B:  SELECT quantity INTO @qb FROM inventory WHERE variant_id = 1;     -- also reads 25
A:  UPDATE inventory SET quantity = @qa - 1 WHERE variant_id = 1;  COMMIT;   -- 24
B:  UPDATE inventory SET quantity = @qb - 1 WHERE variant_id = 1;  COMMIT;   -- 24 again!
A:  SELECT quantity FROM inventory WHERE variant_id = 1;   -- 24, but 2 units were sold (should be 23)
    Schedule: r_A(X) r_B(X) w_A(X) w_B(X) -> not conflict-serializable (see below).
A:  UPDATE inventory SET quantity = 25 WHERE variant_id = 1;          -- restore

(b) WITH SELECT ... FOR UPDATE -> both sales counted
A:  START TRANSACTION;
A:  SELECT quantity INTO @qa FROM inventory WHERE variant_id = 1 FOR UPDATE;   -- 25, X lock
B:  START TRANSACTION;
B:  SELECT quantity INTO @qb FROM inventory WHERE variant_id = 1 FOR UPDATE;   -- B WAITS
A:  UPDATE inventory SET quantity = @qa - 1 WHERE variant_id = 1;  COMMIT;     -- 24, lock released
    -- B now continues and reads 24 (not 25)
B:  UPDATE inventory SET quantity = @qb - 1 WHERE variant_id = 1;  COMMIT;     -- 23  (correct)
A:  UPDATE inventory SET quantity = 25 WHERE variant_id = 1;                    -- restore
    This is exactly what place_marketplace_order does, so orders can never
    lose a stock update.


7.6 SERIALIZABLE ISOLATION LEVEL: reads block conflicting writes
----------------------------------------------------------------
A:  SET SESSION TRANSACTION ISOLATION LEVEL SERIALIZABLE;
A:  START TRANSACTION;
A:  SELECT reorder_level FROM inventory WHERE variant_id = 1;         -- plain read takes an S lock

B:  SET SESSION innodb_lock_wait_timeout = 5;
B:  UPDATE inventory SET reorder_level = reorder_level WHERE variant_id = 1;
    -- B WAITS, then: ERROR 1205 (HY000): Lock wait timeout exceeded
    -- (repeat with A at REPEATABLE READ: B's UPDATE runs immediately)

A:  COMMIT;
A:  SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ;         -- back to default


7.7 DEADLOCK DETECTION
----------------------
A:  START TRANSACTION;
A:  UPDATE inventory SET reorder_level = reorder_level WHERE variant_id = 1;   -- A locks row 1
B:  START TRANSACTION;
B:  UPDATE inventory SET reorder_level = reorder_level WHERE variant_id = 2;   -- B locks row 2
A:  UPDATE inventory SET reorder_level = reorder_level WHERE variant_id = 2;   -- A WAITS for B
B:  UPDATE inventory SET reorder_level = reorder_level WHERE variant_id = 1;   -- cycle!
    -- B: ERROR 1213 (40001): Deadlock found when trying to get lock;
    --    try restarting transaction
    -- InnoDB detects the wait-for cycle at once, rolls back B (the victim)
    -- and A's waiting UPDATE completes.
A:  COMMIT;
    SHOW ENGINE INNODB STATUS;   -- section "LATEST DETECTED DEADLOCK" shows both transactions
    Prevention used in this project: every procedure locks rows in the same
    order (order -> inventory), so the procedures cannot deadlock each other.
*/


-- ---------------------------------------------------------------------------
-- 7.8 SERIALIZABILITY: THEORY BEHIND THE DEMONSTRATIONS
-- ---------------------------------------------------------------------------
-- Schedule: the order in which the operations of concurrent transactions
-- run. A schedule is SERIALIZABLE if its result equals some serial schedule
-- (T1 entirely before T2, or T2 entirely before T1).
--
-- Conflicting operations: two operations on the same item X, from different
-- transactions, where at least one is a write:  r-w, w-r, w-w.
--
-- Conflict serializability test (precedence graph): draw an edge Ti -> Tj
-- when an operation of Ti conflicts with, and comes before, one of Tj.
-- The schedule is conflict-serializable  <=>  the graph has no cycle.
--
-- Lost-update schedule from 7.5(a):   r_A(X)  r_B(X)  w_A(X)  w_B(X)
--   r_A(X) before w_B(X)  ->  edge A -> B
--   r_B(X) before w_A(X)  ->  edge B -> A
--   Cycle A -> B -> A     ->  NOT conflict-serializable  (one update lost)
--
-- Locked schedule from 7.5(b):        r_A(X) w_A(X) c_A  r_B(X) w_B(X) c_B
--   Only edges A -> B, no cycle       ->  serializable (equivalent to A then B)
--
-- How MySQL/InnoDB guarantees it: STRICT TWO-PHASE LOCKING (Strict 2PL).
--   * Growing phase:   a transaction acquires locks as it reads/writes
--                      (S for SERIALIZABLE reads and LOCK IN SHARE MODE,
--                       X for writes and SELECT ... FOR UPDATE).
--   * Shrinking phase: locks are released only at COMMIT / ROLLBACK.
--   Two-phase locking guarantees conflict-serializable schedules; holding
--   locks until commit (strict) also prevents cascading rollbacks.
--   Tests C1-C2 and S1-S2 show the X and S locks being taken and released;
--   7.7 shows that 2PL can deadlock and that InnoDB resolves it.


-- ---------------------------------------------------------------------------
-- 8. OPTIONAL: inspect the stored procedure definition
-- ---------------------------------------------------------------------------
-- SHOW CREATE PROCEDURE place_marketplace_order;
