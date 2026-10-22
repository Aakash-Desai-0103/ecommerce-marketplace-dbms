USE ecommerce_marketplace;

-- ============================================================
-- WEEK 4 — FUNCTIONS, PROCEDURES, COMMON TABLE EXPRESSIONS
-- Run after week3_database_objects.sql (procedures rely on the
-- Week 3 stock triggers). Safe to re-run.
-- ============================================================


-- ============================================================
-- SECTION 1: FUNCTIONS
-- These read table data, so they are declared NOT DETERMINISTIC
-- READS SQL DATA (results change when the data changes).
-- ============================================================

-- 1.1 Average rating of a product
DROP FUNCTION IF EXISTS fn_product_avg_rating;
DELIMITER $$
CREATE FUNCTION fn_product_avg_rating(p_product_id BIGINT UNSIGNED)
RETURNS DECIMAL(3,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_avg DECIMAL(3,2);

    SELECT ROUND(AVG(rating), 2) INTO v_avg
    FROM review
    WHERE product_id = p_product_id;

    RETURN IFNULL(v_avg, 0.00);
END $$
DELIMITER ;


-- 1.2 Current stock quantity of a variant
DROP FUNCTION IF EXISTS fn_variant_stock;
DELIMITER $$
CREATE FUNCTION fn_variant_stock(p_variant_id BIGINT UNSIGNED)
RETURNS INT
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_qty INT;

    SELECT quantity INTO v_qty
    FROM inventory
    WHERE variant_id = p_variant_id;

    RETURN IFNULL(v_qty, 0);
END $$
DELIMITER ;


-- 1.3 Subtotal of an order (sum of quantity * unit_price, before coupons)
DROP FUNCTION IF EXISTS fn_order_total;
DELIMITER $$
CREATE FUNCTION fn_order_total(p_order_id BIGINT UNSIGNED)
RETURNS DECIMAL(10,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2);

    SELECT SUM(quantity * unit_price) INTO v_total
    FROM order_item
    WHERE order_id = p_order_id;

    RETURN IFNULL(v_total, 0.00);
END $$
DELIMITER ;


-- 1.4 Lifetime revenue earned by a seller (cancelled orders excluded)
DROP FUNCTION IF EXISTS fn_seller_revenue;
DELIMITER $$
CREATE FUNCTION fn_seller_revenue(p_seller_id BIGINT UNSIGNED)
RETURNS DECIMAL(12,2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_revenue DECIMAL(12,2);

    SELECT SUM(oi.quantity * oi.unit_price) INTO v_revenue
    FROM order_item oi
    JOIN orders o ON o.order_id = oi.order_id
    JOIN product_variant pv ON oi.variant_id = pv.variant_id
    JOIN product p ON pv.product_id = p.product_id
    WHERE p.seller_id = p_seller_id
      AND o.status <> 'CANCELLED';

    RETURN IFNULL(v_revenue, 0.00);
END $$
DELIMITER ;


-- Quick tests
SELECT fn_product_avg_rating(1) AS iphone_avg_rating;
SELECT fn_variant_stock(10)     AS kallax_stock;
SELECT fn_order_total(6)        AS order_6_subtotal;
SELECT fn_seller_revenue(5)     AS techworld_revenue;


-- ============================================================
-- SECTION 2: STORED PROCEDURES
-- Validation errors are raised with SIGNAL SQLSTATE '45000'.
-- Every procedure that changes more than one row runs as ONE
-- transaction: START TRANSACTION ... COMMIT, and an EXIT handler
-- that ROLLBACKs and re-raises the error. The rows a procedure
-- depends on are locked with SELECT ... FOR UPDATE, so two users
-- running the same procedure on the same data are serialised
-- (see week6.sql for the serializability demonstrations).
-- ============================================================

-- 2.1 Add a new product variant + its inventory row in one call
DROP PROCEDURE IF EXISTS sp_add_product_variant;
DELIMITER $$
CREATE PROCEDURE sp_add_product_variant(
    IN  p_product_id   BIGINT UNSIGNED,
    IN  p_sku          VARCHAR(100),
    IN  p_price        DECIMAL(10,2),
    IN  p_initial_qty  INT UNSIGNED,
    IN  p_reorder_lvl  INT UNSIGNED,
    OUT p_variant_id   BIGINT UNSIGNED
)
BEGIN
    DECLARE v_inventory_id BIGINT UNSIGNED;

    -- Any error (validation SIGNAL, constraint, trigger) undoes all work
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM product WHERE product_id = p_product_id) THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Product does not exist.';
    END IF;

    INSERT INTO product_variant (product_id, sku, price)
    VALUES (p_product_id, p_sku, p_price);

    SET p_variant_id = LAST_INSERT_ID();

    INSERT INTO inventory (variant_id, quantity, reorder_level)
    VALUES (p_variant_id, p_initial_qty, p_reorder_lvl);

    SET v_inventory_id = LAST_INSERT_ID();

    -- Record opening stock in the ledger
    IF p_initial_qty > 0 THEN
        INSERT INTO inventory_transaction
            (inventory_id, transaction_type, quantity, reference_type, reference_id)
        VALUES
            (v_inventory_id, 'RESTOCK', p_initial_qty, 'INITIAL_STOCK', NULL);
    END IF;

    COMMIT;
END $$
DELIMITER ;


-- 2.2 Add one line to an existing, still-open order.
--     Price is taken from the catalog; stock is validated and reduced
--     by the Week 3 triggers; the order total is kept in sync.
DROP PROCEDURE IF EXISTS sp_add_order_item;
DELIMITER $$
CREATE PROCEDURE sp_add_order_item(
    IN p_order_id   BIGINT UNSIGNED,
    IN p_variant_id BIGINT UNSIGNED,
    IN p_quantity   INT UNSIGNED
)
BEGIN
    DECLARE v_price  DECIMAL(10,2);
    DECLARE v_status VARCHAR(20);

    -- Any error (validation SIGNAL, constraint, trigger) undoes all work
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Lock the order row: no one else can change this order until COMMIT
    SELECT status INTO v_status
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist.';
    ELSEIF v_status NOT IN ('PENDING', 'CONFIRMED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Items can only be added to PENDING or CONFIRMED orders.';
    END IF;

    -- An order that is already paid cannot change amount any more
    IF EXISTS (SELECT 1 FROM payment
               WHERE order_id = p_order_id AND payment_status <> 'PENDING') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order is already paid; its amount cannot change.';
    END IF;

    IF p_quantity IS NULL OR p_quantity = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Quantity must be greater than zero.';
    END IF;

    SELECT price INTO v_price
    FROM product_variant
    WHERE variant_id = p_variant_id;

    IF v_price IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Product variant does not exist.';
    END IF;

    -- Week 3 triggers: stock check (BEFORE) + stock reduction and ledger entry (AFTER)
    INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
    VALUES (p_order_id, p_variant_id, p_quantity, v_price);

    UPDATE orders
    SET total_amount = total_amount + (v_price * p_quantity)
    WHERE order_id = p_order_id;

    UPDATE payment
    SET amount = amount + (v_price * p_quantity)
    WHERE order_id = p_order_id
      AND payment_status = 'PENDING';

    COMMIT;
END $$
DELIMITER ;


-- 2.3 Raise a return for a delivered order item and record its refund.
--     The refund cannot exceed what was paid for that line.
DROP PROCEDURE IF EXISTS sp_process_return;
DELIMITER $$
CREATE PROCEDURE sp_process_return(
    IN p_order_item_id BIGINT UNSIGNED,
    IN p_reason        VARCHAR(500),
    IN p_payment_id    BIGINT UNSIGNED,
    IN p_refund_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_order_id       BIGINT UNSIGNED;
    DECLARE v_order_status   VARCHAR(20);
    DECLARE v_line_value     DECIMAL(10,2);
    DECLARE v_payment_order  BIGINT UNSIGNED;
    DECLARE v_payment_status VARCHAR(20);
    DECLARE v_return_id      BIGINT UNSIGNED;

    -- Any error (validation SIGNAL, constraint, trigger) undoes all work
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Lock the order item (and its order) so the same item cannot be
    -- returned twice by two concurrent requests
    SELECT oi.order_id, o.status, oi.quantity * oi.unit_price
      INTO v_order_id, v_order_status, v_line_value
    FROM order_item oi
    JOIN orders o ON o.order_id = oi.order_id
    WHERE oi.order_item_id = p_order_item_id
    FOR UPDATE;

    IF v_order_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order item does not exist.';
    ELSEIF v_order_status <> 'DELIVERED' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only delivered orders can be returned.';
    END IF;

    IF EXISTS (
        SELECT 1 FROM return_request
        WHERE order_item_id = p_order_item_id
          AND status <> 'REJECTED'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A return already exists for this order item.';
    END IF;

    SELECT order_id, payment_status
      INTO v_payment_order, v_payment_status
    FROM payment
    WHERE payment_id = p_payment_id
    FOR UPDATE;

    IF v_payment_order IS NULL OR v_payment_order <> v_order_id THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Payment does not belong to this order.';
    ELSEIF v_payment_status <> 'SUCCESS' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only successful payments can be refunded.';
    END IF;

    IF p_refund_amount <= 0 OR p_refund_amount > v_line_value THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Refund must be positive and not exceed the item value.';
    END IF;

    INSERT INTO return_request (order_item_id, reason, status, resolved_at)
    VALUES (p_order_item_id, p_reason, 'APPROVED', CURRENT_TIMESTAMP);

    SET v_return_id = LAST_INSERT_ID();

    INSERT INTO refund (return_id, payment_id, amount, refund_status)
    VALUES (v_return_id, p_payment_id, p_refund_amount, 'PENDING');

    COMMIT;
END $$
DELIMITER ;


-- 2.4 Apply a coupon to an order after validating it, computing the
--     discount and updating the order total (and pending payment).
DROP PROCEDURE IF EXISTS sp_apply_coupon;
DELIMITER $$
CREATE PROCEDURE sp_apply_coupon(
    IN p_order_id  BIGINT UNSIGNED,
    IN p_coupon_id BIGINT UNSIGNED
)
BEGIN
    DECLARE v_order_status VARCHAR(20);
    DECLARE v_order_date   DATETIME;
    DECLARE v_subtotal     DECIMAL(10,2);
    DECLARE v_type         VARCHAR(20);
    DECLARE v_value        DECIMAL(10,2);
    DECLARE v_minimum      DECIMAL(10,2);
    DECLARE v_start        DATETIME;
    DECLARE v_expiry       DATETIME;
    DECLARE v_limit        INT UNSIGNED;
    DECLARE v_times_used   INT;
    DECLARE v_discount     DECIMAL(10,2);

    -- Any error (validation SIGNAL, constraint, trigger) undoes all work
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT status, order_date INTO v_order_status, v_order_date
    FROM orders
    WHERE order_id = p_order_id
    FOR UPDATE;

    IF v_order_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not exist.';
    ELSEIF v_order_status NOT IN ('PENDING', 'CONFIRMED') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Coupons can only be applied to PENDING or CONFIRMED orders.';
    END IF;

    -- An order that is already paid cannot change amount any more
    IF EXISTS (SELECT 1 FROM payment
               WHERE order_id = p_order_id AND payment_status <> 'PENDING') THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order is already paid; its amount cannot change.';
    END IF;

    IF EXISTS (SELECT 1 FROM order_coupon WHERE order_id = p_order_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'A coupon is already applied to this order.';
    END IF;

    SELECT discount_type, discount_value, minimum_amount, start_date, expiry_date, usage_limit
      INTO v_type, v_value, v_minimum, v_start, v_expiry, v_limit
    FROM coupon
    WHERE coupon_id = p_coupon_id
    FOR UPDATE;    -- serialises concurrent use of the same coupon, so the
                   -- usage-limit check below cannot be passed twice at once

    IF v_type IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Coupon does not exist.';
    END IF;

    IF v_order_date NOT BETWEEN v_start AND v_expiry THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Coupon is not valid on the order date.';
    END IF;

    SELECT COUNT(*) INTO v_times_used
    FROM order_coupon
    WHERE coupon_id = p_coupon_id;

    IF v_limit IS NOT NULL AND v_times_used >= v_limit THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Coupon usage limit reached.';
    END IF;

    SET v_subtotal = fn_order_total(p_order_id);

    IF v_subtotal < v_minimum THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Order does not meet the coupon minimum amount.';
    END IF;

    IF v_type = 'PERCENTAGE' THEN
        SET v_discount = ROUND(v_subtotal * v_value / 100, 2);
    ELSE
        SET v_discount = LEAST(v_value, v_subtotal);
    END IF;

    INSERT INTO order_coupon (order_id, coupon_id, discount_amount)
    VALUES (p_order_id, p_coupon_id, v_discount);

    UPDATE orders
    SET total_amount = total_amount - v_discount
    WHERE order_id = p_order_id;

    UPDATE payment
    SET amount = amount - v_discount
    WHERE order_id = p_order_id
      AND payment_status = 'PENDING';

    COMMIT;

    SELECT p_order_id AS order_id, v_subtotal AS subtotal,
           v_discount AS discount, v_subtotal - v_discount AS payable;
END $$
DELIMITER ;


-- Quick tests (these change data; run individually)
-- CALL sp_add_product_variant(1, 'IPH16-512-BLK', 99999.00, 10, 3, @vid);
-- SELECT @vid;
-- CALL sp_add_order_item(3, 7, 1);           -- rejected: order 3 is already paid
-- (use an unpaid PENDING order, e.g. one placed with place_marketplace_order in week6.sql)
-- CALL sp_process_return(7, 'Scroll wheel faulty', 6, 8495.00);
-- CALL sp_process_return(4, 'Test', 4, 100); -- rejected: order 4 not delivered
-- CALL sp_apply_coupon(3, 1);                -- rejected: order 3 already has a coupon
--
-- Atomicity check: a failure part-way through rolls everything back.
-- On an unpaid PENDING order (id from week6.sql), 999 units of variant 7
-- fails on the order_item insert (Week 3 stock trigger); the order total
-- and payment must be unchanged afterwards.
-- SELECT total_amount FROM orders WHERE order_id = <id>;
-- CALL sp_add_order_item(<id>, 7, 999);      -- ERROR: Insufficient stock
-- SELECT total_amount FROM orders WHERE order_id = <id>;   -- same as before


-- ============================================================
-- SECTION 3: COMMON TABLE EXPRESSIONS (CTEs)
-- ============================================================

-- 3.1 Simple CTE: products with below-reorder-level stock
WITH low_stock AS (
    SELECT pv.variant_id, pv.product_id, i.quantity, i.reorder_level
    FROM inventory i
    JOIN product_variant pv ON i.variant_id = pv.variant_id
    WHERE i.quantity <= i.reorder_level
)
SELECT p.name AS product_name, ls.quantity, ls.reorder_level
FROM low_stock ls
JOIN product p ON ls.product_id = p.product_id;


-- 3.2 CTE replacing the Week 2 "derived table" top-spenders query
WITH customer_spend AS (
    SELECT o.user_id, SUM(oi.quantity * oi.unit_price) AS total_spent
    FROM orders o
    JOIN order_item oi ON o.order_id = oi.order_id
    WHERE o.status <> 'CANCELLED'
    GROUP BY o.user_id
)
SELECT u.name, cs.total_spent
FROM customer_spend cs
JOIN users u ON cs.user_id = u.user_id
ORDER BY cs.total_spent DESC
LIMIT 5;


-- 3.3 Multiple chained CTEs: monthly revenue per seller
WITH order_line_revenue AS (
    SELECT
        p.seller_id,
        o.order_id,
        DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        (oi.quantity * oi.unit_price) AS line_revenue
    FROM order_item oi
    JOIN orders o ON oi.order_id = o.order_id
    JOIN product_variant pv ON oi.variant_id = pv.variant_id
    JOIN product p ON pv.product_id = p.product_id
    WHERE o.status <> 'CANCELLED'
),
seller_monthly_revenue AS (
    SELECT seller_id, order_month, SUM(line_revenue) AS monthly_revenue
    FROM order_line_revenue
    GROUP BY seller_id, order_month
)
SELECT sp.user_id AS seller_user_id, sp.store_name, smr.order_month, smr.monthly_revenue
FROM seller_monthly_revenue smr
JOIN seller_profile sp ON smr.seller_id = sp.user_id
ORDER BY sp.user_id, smr.order_month;


-- 3.4 CTE combined with a Week 4 function call
WITH category_products AS (
    SELECT pc.category_id, p.product_id, p.name
    FROM product_category pc
    JOIN product p ON pc.product_id = p.product_id
)
SELECT
    c.name AS category_name,
    cp.name AS product_name,
    fn_product_avg_rating(cp.product_id) AS avg_rating
FROM category_products cp
JOIN category c ON cp.category_id = c.category_id
ORDER BY avg_rating DESC;


-- 3.5 CTE isolating high-value customers, then filtering with HAVING
WITH order_totals AS (
    SELECT order_id, user_id, fn_order_total(order_id) AS order_value
    FROM orders
    WHERE status <> 'CANCELLED'
)
SELECT user_id, COUNT(*) AS num_orders, SUM(order_value) AS lifetime_value
FROM order_totals
GROUP BY user_id
HAVING SUM(order_value) > 50000;



-- 3.6 Recursive CTE: daily order count for 10-31 Aug 2026, including days
--     with no orders (the recursion generates one row per calendar day)
WITH RECURSIVE calendar (day) AS (
    SELECT DATE('2026-08-10')              -- anchor member
    UNION ALL
    SELECT day + INTERVAL 1 DAY            -- recursive member
    FROM calendar
    WHERE day < '2026-08-31'               -- termination condition
)
SELECT c.day,
       COUNT(o.order_id) AS orders_placed
FROM calendar c
LEFT JOIN orders o
    ON DATE(o.order_date) = c.day
GROUP BY c.day
ORDER BY c.day;
