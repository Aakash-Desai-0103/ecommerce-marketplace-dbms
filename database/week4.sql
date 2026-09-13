-- ============================================================
-- WEEK 4 — FUNCTIONS, PROCEDURES, COMMON TABLE EXPRESSIONS
-- ============================================================


-- ============================================================
-- SECTION 1: FUNCTIONS
-- ============================================================

-- 1.1 Average rating of a product
DROP FUNCTION IF EXISTS fn_product_avg_rating;
DELIMITER $$
CREATE FUNCTION fn_product_avg_rating(p_product_id INT)
RETURNS DECIMAL(3,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_avg DECIMAL(3,2);

    SELECT ROUND(AVG(rating), 2) INTO v_avg
    FROM REVIEW
    WHERE product_id = p_product_id;

    RETURN IFNULL(v_avg, 0.00);
END $$
DELIMITER ;


-- 1.2 Current stock quantity of a variant
DROP FUNCTION IF EXISTS fn_variant_stock;
DELIMITER $$
CREATE FUNCTION fn_variant_stock(p_variant_id INT)
RETURNS INT
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_qty INT;

    SELECT quantity INTO v_qty
    FROM INVENTORY
    WHERE variant_id = p_variant_id;

    RETURN IFNULL(v_qty, 0);
END $$
DELIMITER ;


-- 1.3 Total value of an order (sum of quantity * unit_price across items)
DROP FUNCTION IF EXISTS fn_order_total;
DELIMITER $$
CREATE FUNCTION fn_order_total(p_order_id INT)
RETURNS DECIMAL(10,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_total DECIMAL(10,2);

    SELECT SUM(quantity * unit_price) INTO v_total
    FROM ORDER_ITEM
    WHERE order_id = p_order_id;

    RETURN IFNULL(v_total, 0.00);
END $$
DELIMITER ;


-- 1.4 Lifetime revenue earned by a seller (sum across all their products' order items)
DROP FUNCTION IF EXISTS fn_seller_revenue;
DELIMITER $$
CREATE FUNCTION fn_seller_revenue(p_seller_id INT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_revenue DECIMAL(12,2);

    SELECT SUM(oi.quantity * oi.unit_price) INTO v_revenue
    FROM ORDER_ITEM oi
    JOIN PRODUCT_VARIANT pv ON oi.variant_id = pv.variant_id
    JOIN PRODUCT p ON pv.product_id = p.product_id
    WHERE p.seller_id = p_seller_id;

    RETURN IFNULL(v_revenue, 0.00);
END $$
DELIMITER ;


-- Quick tests:
-- SELECT fn_product_avg_rating(1);
-- SELECT fn_variant_stock(1);
-- SELECT fn_order_total(1);
-- SELECT fn_seller_revenue(1);


-- ============================================================
-- SECTION 2: STORED PROCEDURES
-- ============================================================

-- 2.1 Add a new product variant + its inventory row in one call
DROP PROCEDURE IF EXISTS sp_add_product_variant;
DELIMITER $$
CREATE PROCEDURE sp_add_product_variant(
    IN p_product_id   INT,
    IN p_sku          VARCHAR(64),
    IN p_price        DECIMAL(10,2),
    IN p_initial_qty  INT,
    IN p_reorder_lvl  INT,
    OUT p_variant_id  INT
)
BEGIN
    INSERT INTO PRODUCT_VARIANT (product_id, sku, price)
    VALUES (p_product_id, p_sku, p_price);

    SET p_variant_id = LAST_INSERT_ID();

    INSERT INTO INVENTORY (variant_id, quantity, reorder_level)
    VALUES (p_variant_id, p_initial_qty, p_reorder_lvl);
END $$
DELIMITER ;


-- 2.2 Place an order from a set of cart items (simplified: one variant + qty per call
--     inside a loop on the application side, OR extend with a JSON/temp-table approach
--     later once cursors/JSON topics are covered). This version places a single-item
--     order line and grows the order if it already exists.
DROP PROCEDURE IF EXISTS sp_add_order_item;
DELIMITER $$
CREATE PROCEDURE sp_add_order_item(
    IN p_order_id   INT,
    IN p_variant_id INT,
    IN p_quantity   INT
)
BEGIN
    DECLARE v_price DECIMAL(10,2);

    SELECT price INTO v_price
    FROM PRODUCT_VARIANT
    WHERE variant_id = p_variant_id;

    INSERT INTO ORDER_ITEM (order_id, variant_id, quantity, unit_price)
    VALUES (p_order_id, p_variant_id, p_quantity, v_price);

    -- NOTE: inventory reduction is already handled by the
    -- Week 3 trigger on ORDER_ITEM insertion, so it is NOT
    -- duplicated here.
END $$
DELIMITER ;


-- 2.3 Process a return request into a refund
DROP PROCEDURE IF EXISTS sp_process_return;
DELIMITER $$
CREATE PROCEDURE sp_process_return(
    IN p_order_item_id INT,
    IN p_reason        VARCHAR(255),
    IN p_payment_id     INT,
    IN p_refund_amount DECIMAL(10,2)
)
BEGIN
    DECLARE v_return_id INT;

    INSERT INTO RETURN_REQUEST (order_item_id, reason, status)
    VALUES (p_order_item_id, p_reason, 'APPROVED');

    SET v_return_id = LAST_INSERT_ID();

    INSERT INTO REFUND (return_id, payment_id, amount, refund_status)
    VALUES (v_return_id, p_payment_id, p_refund_amount, 'PROCESSED');

    -- NOTE: the Week 3 "order cancellation restores inventory" trigger
    -- pattern can be mirrored here later if RETURN_REQUEST is wired to
    -- an inventory-restoring trigger; left as-is for now since that
    -- trigger already exists for cancellations, not returns.
END $$
DELIMITER ;


-- 2.4 Apply a coupon to an order, after validating it isn't already applied
DROP PROCEDURE IF EXISTS sp_apply_coupon;
DELIMITER $$
CREATE PROCEDURE sp_apply_coupon(
    IN p_order_id  INT,
    IN p_coupon_id INT
)
BEGIN
    DECLARE v_exists INT;

    SELECT COUNT(*) INTO v_exists
    FROM ORDER_COUPON
    WHERE order_id = p_order_id AND coupon_id = p_coupon_id;

    IF v_exists = 0 THEN
        INSERT INTO ORDER_COUPON (order_id, coupon_id)
        VALUES (p_order_id, p_coupon_id);
    ELSE
        SELECT 'Coupon already applied to this order' AS message;
    END IF;
END $$
DELIMITER ;


-- Quick tests:
-- CALL sp_add_product_variant(1, 'SKU-001-BLK', 999.00, 50, 10, @vid);
-- SELECT @vid;
-- CALL sp_add_order_item(1, 1, 2);
-- CALL sp_process_return(1, 'Item damaged on arrival', 1, 999.00);
-- CALL sp_apply_coupon(1, 1);


-- ============================================================
-- SECTION 3: COMMON TABLE EXPRESSIONS (CTEs)
-- ============================================================

-- 3.1 Simple CTE: products with below-reorder-level stock
WITH low_stock AS (
    SELECT pv.variant_id, pv.product_id, i.quantity, i.reorder_level
    FROM INVENTORY i
    JOIN PRODUCT_VARIANT pv ON i.variant_id = pv.variant_id
    WHERE i.quantity <= i.reorder_level
)
SELECT p.name AS product_name, ls.quantity, ls.reorder_level
FROM low_stock ls
JOIN PRODUCT p ON ls.product_id = p.product_id;


-- 3.2 CTE replacing the Week 2 "derived table" top-spenders query
WITH customer_spend AS (
    SELECT o.user_id, SUM(oi.quantity * oi.unit_price) AS total_spent
    FROM ORDERS o
    JOIN ORDER_ITEM oi ON o.order_id = oi.order_id
    GROUP BY o.user_id
)
SELECT u.name, cs.total_spent
FROM customer_spend cs
JOIN USERS u ON cs.user_id = u.user_id
ORDER BY cs.total_spent DESC
LIMIT 5;


-- 3.3 Multiple chained CTEs: monthly revenue per seller
WITH order_line_revenue AS (
    SELECT
        p.seller_id,
        o.order_id,
        DATE_FORMAT(o.order_date, '%Y-%m') AS order_month,
        (oi.quantity * oi.unit_price) AS line_revenue
    FROM ORDER_ITEM oi
    JOIN ORDERS o ON oi.order_id = o.order_id
    JOIN PRODUCT_VARIANT pv ON oi.variant_id = pv.variant_id
    JOIN PRODUCT p ON pv.product_id = p.product_id
),
seller_monthly_revenue AS (
    SELECT seller_id, order_month, SUM(line_revenue) AS monthly_revenue
    FROM order_line_revenue
    GROUP BY seller_id, order_month
)
SELECT sp.user_id AS seller_user_id, smr.order_month, smr.monthly_revenue
FROM seller_monthly_revenue smr
JOIN SELLER_PROFILE sp ON smr.seller_id = sp.user_id
ORDER BY sp.user_id, smr.order_month;


-- 3.4 CTE combined with a Week 4 function call
WITH category_products AS (
    SELECT pc.category_id, p.product_id, p.name
    FROM PRODUCT_CATEGORY pc
    JOIN PRODUCT p ON pc.product_id = p.product_id
)
SELECT
    c.name AS category_name,
    cp.name AS product_name,
    fn_product_avg_rating(cp.product_id) AS avg_rating
FROM category_products cp
JOIN CATEGORY c ON cp.category_id = c.category_id
ORDER BY avg_rating DESC;


-- 3.5 CTE isolating high-value customers, then filtering with HAVING
WITH order_totals AS (
    SELECT order_id, user_id, fn_order_total(order_id) AS order_value
    FROM ORDERS
)
SELECT user_id, COUNT(*) AS num_orders, SUM(order_value) AS lifetime_value
FROM order_totals
GROUP BY user_id
HAVING SUM(order_value) > 50000;