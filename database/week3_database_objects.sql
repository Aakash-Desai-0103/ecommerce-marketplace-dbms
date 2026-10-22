USE ecommerce_marketplace;

-- =====================================================================
-- WEEK 3 — DATABASE OBJECTS: VIEWS, USERS & ROLES, TRIGGERS
-- Run after seed.sql. Safe to re-run.
-- =====================================================================


-- =====================================================================
-- 1. VIEWS
-- =====================================================================

-- 1.1 Product catalog view
-- Displays product, seller, variant and inventory information
CREATE OR REPLACE VIEW vw_product_catalog AS
SELECT
    p.product_id,
    p.name AS product_name,
    p.status AS product_status,
    sp.store_name,
    pv.variant_id,
    pv.sku,
    pv.price,
    i.quantity AS stock_quantity,
    i.reorder_level
FROM product p
JOIN seller_profile sp
    ON sp.user_id = p.seller_id
JOIN product_variant pv
    ON pv.product_id = p.product_id
JOIN inventory i
    ON i.variant_id = pv.variant_id;


-- 1.2 Customer order history view
CREATE OR REPLACE VIEW vw_customer_order_history AS
SELECT
    u.user_id,
    u.name AS customer_name,
    o.order_id,
    o.order_date,
    o.status AS order_status,
    o.total_amount
FROM users u
JOIN orders o
    ON o.user_id = u.user_id;


-- 1.3 Seller sales summary view (cancelled orders are not revenue)
CREATE OR REPLACE VIEW vw_seller_sales_summary AS
SELECT
    sp.user_id AS seller_id,
    sp.store_name,
    COUNT(DISTINCT p.product_id) AS total_products,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue
FROM seller_profile sp
LEFT JOIN product p
    ON p.seller_id = sp.user_id
LEFT JOIN product_variant pv
    ON pv.product_id = p.product_id
LEFT JOIN (
    SELECT oi2.order_id, oi2.variant_id, oi2.quantity, oi2.unit_price
    FROM order_item oi2
    JOIN orders o
        ON o.order_id = oi2.order_id
    WHERE o.status <> 'CANCELLED'
) AS oi
    ON oi.variant_id = pv.variant_id
GROUP BY sp.user_id, sp.store_name;


-- 1.4 Low stock products view
CREATE OR REPLACE VIEW vw_low_stock_products AS
SELECT
    p.product_id,
    p.name AS product_name,
    pv.variant_id,
    pv.sku,
    i.quantity,
    i.reorder_level
FROM product p
JOIN product_variant pv
    ON pv.product_id = p.product_id
JOIN inventory i
    ON i.variant_id = pv.variant_id
WHERE i.quantity <= i.reorder_level;


-- Demonstrating the views
SELECT * FROM vw_product_catalog;

SELECT * FROM vw_customer_order_history;

SELECT * FROM vw_seller_sales_summary;

SELECT * FROM vw_low_stock_products;


-- =====================================================================
-- 2. USERS AND ROLES
-- =====================================================================

-- Remove objects from a previous run so the script can be re-run
DROP USER IF EXISTS 'customer_user'@'localhost';
DROP USER IF EXISTS 'seller_user'@'localhost';
DROP USER IF EXISTS 'admin_user'@'localhost';

DROP ROLE IF EXISTS marketplace_customer;
DROP ROLE IF EXISTS marketplace_seller;
DROP ROLE IF EXISTS marketplace_admin;


-- ---------------------------------------------------------------------
-- CREATE DATABASE ROLES
-- ---------------------------------------------------------------------

CREATE ROLE marketplace_customer;
CREATE ROLE marketplace_seller;
CREATE ROLE marketplace_admin;


-- ---------------------------------------------------------------------
-- CUSTOMER ROLE
-- Browse the catalog; manage own cart, wishlist, addresses, orders
-- and reviews. No access to the raw users table (password hashes).
-- ---------------------------------------------------------------------

GRANT SELECT ON ecommerce_marketplace.vw_product_catalog TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.product            TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.product_variant    TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.product_image      TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.product_category   TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.category           TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.brand              TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.inventory          TO marketplace_customer;
GRANT SELECT ON ecommerce_marketplace.coupon             TO marketplace_customer;

GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce_marketplace.cart_item     TO marketplace_customer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce_marketplace.wishlist_item TO marketplace_customer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce_marketplace.address       TO marketplace_customer;
GRANT SELECT, INSERT                 ON ecommerce_marketplace.cart          TO marketplace_customer;
GRANT SELECT, INSERT                 ON ecommerce_marketplace.wishlist      TO marketplace_customer;

GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.orders         TO marketplace_customer;
GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.order_item     TO marketplace_customer;
GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.review         TO marketplace_customer;
GRANT SELECT, INSERT         ON ecommerce_marketplace.return_request TO marketplace_customer;
GRANT SELECT                 ON ecommerce_marketplace.payment        TO marketplace_customer;
GRANT SELECT                 ON ecommerce_marketplace.shipment       TO marketplace_customer;


-- ---------------------------------------------------------------------
-- SELLER ROLE
-- Manage own catalog and stock; view orders; update shipments.
-- ---------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.product           TO marketplace_seller;
GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.product_variant   TO marketplace_seller;
GRANT SELECT, INSERT, UPDATE, DELETE ON ecommerce_marketplace.product_image    TO marketplace_seller;
GRANT SELECT, INSERT, DELETE         ON ecommerce_marketplace.product_category TO marketplace_seller;
GRANT SELECT, INSERT, DELETE         ON ecommerce_marketplace.variant_attribute TO marketplace_seller;
GRANT SELECT ON ecommerce_marketplace.brand           TO marketplace_seller;
GRANT SELECT ON ecommerce_marketplace.category        TO marketplace_seller;
GRANT SELECT ON ecommerce_marketplace.attribute       TO marketplace_seller;
GRANT SELECT ON ecommerce_marketplace.attribute_value TO marketplace_seller;

GRANT SELECT, INSERT, UPDATE ON ecommerce_marketplace.inventory             TO marketplace_seller;
GRANT SELECT, INSERT         ON ecommerce_marketplace.inventory_transaction TO marketplace_seller;

GRANT SELECT         ON ecommerce_marketplace.orders         TO marketplace_seller;
GRANT SELECT         ON ecommerce_marketplace.order_item     TO marketplace_seller;
GRANT SELECT, UPDATE ON ecommerce_marketplace.shipment       TO marketplace_seller;
GRANT SELECT, UPDATE ON ecommerce_marketplace.return_request TO marketplace_seller;
GRANT SELECT         ON ecommerce_marketplace.review         TO marketplace_seller;
GRANT SELECT         ON ecommerce_marketplace.vw_seller_sales_summary TO marketplace_seller;
GRANT SELECT         ON ecommerce_marketplace.vw_low_stock_products   TO marketplace_seller;


-- ---------------------------------------------------------------------
-- ADMIN ROLE
-- Administrator has full access to the project database.
-- ---------------------------------------------------------------------

GRANT ALL PRIVILEGES
ON ecommerce_marketplace.*
TO marketplace_admin;


-- ---------------------------------------------------------------------
-- CREATE DEMONSTRATION DATABASE USERS
-- Demo-only passwords for the lab. The web application will read its
-- own credentials from environment variables, never from source code.
-- ---------------------------------------------------------------------

CREATE USER 'customer_user'@'localhost'
IDENTIFIED BY 'Customer@123';

CREATE USER 'seller_user'@'localhost'
IDENTIFIED BY 'Seller@123';

CREATE USER 'admin_user'@'localhost'
IDENTIFIED BY 'Admin@123';


-- ---------------------------------------------------------------------
-- ASSIGN ROLES TO USERS
-- ---------------------------------------------------------------------

GRANT marketplace_customer
TO 'customer_user'@'localhost';

GRANT marketplace_seller
TO 'seller_user'@'localhost';

GRANT marketplace_admin
TO 'admin_user'@'localhost';


-- ---------------------------------------------------------------------
-- SET DEFAULT ROLES
-- ---------------------------------------------------------------------

SET DEFAULT ROLE marketplace_customer
TO 'customer_user'@'localhost';

SET DEFAULT ROLE marketplace_seller
TO 'seller_user'@'localhost';

SET DEFAULT ROLE marketplace_admin
TO 'admin_user'@'localhost';


-- ---------------------------------------------------------------------
-- VERIFY ROLE ASSIGNMENTS
-- ---------------------------------------------------------------------

SHOW GRANTS FOR 'customer_user'@'localhost' USING marketplace_customer;

SHOW GRANTS FOR 'seller_user'@'localhost' USING marketplace_seller;

SHOW GRANTS FOR 'admin_user'@'localhost' USING marketplace_admin;


-- =====================================================================
-- 3. TRIGGERS
-- All triggers work on the existing 28 tables only.
-- Stock movements are written to inventory_transaction, so the
-- ledger always explains the current inventory.quantity.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_check_stock_before_order_item;
DROP TRIGGER IF EXISTS trg_reduce_inventory;
DROP TRIGGER IF EXISTS trg_restore_inventory_on_cancellation;
DROP TRIGGER IF EXISTS trg_order_status_history;

DELIMITER //

-- =========================================================
-- 1. BEFORE ORDER ITEM INSERT -> VALIDATE STOCK
-- Rejects the insert with a clear message instead of letting
-- the UNSIGNED stock column overflow.
-- =========================================================

CREATE TRIGGER trg_check_stock_before_order_item
BEFORE INSERT ON order_item
FOR EACH ROW
BEGIN
    DECLARE v_stock INT UNSIGNED;

    SELECT quantity INTO v_stock
    FROM inventory
    WHERE variant_id = NEW.variant_id;

    IF v_stock IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'No inventory record exists for this variant.';
    ELSEIF v_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insufficient stock for this variant.';
    END IF;
END//


-- =========================================================
-- 2. ORDER ITEM ADDED -> REDUCE INVENTORY + LOG PURCHASE
-- =========================================================

CREATE TRIGGER trg_reduce_inventory
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
    UPDATE inventory
    SET quantity = quantity - NEW.quantity
    WHERE variant_id = NEW.variant_id;

    INSERT INTO inventory_transaction (
        inventory_id, transaction_type, quantity, reference_type, reference_id
    )
    SELECT
        inventory_id, 'PURCHASE', -CAST(NEW.quantity AS SIGNED), 'ORDER', NEW.order_id
    FROM inventory
    WHERE variant_id = NEW.variant_id;
END//


-- =========================================================
-- 3. ORDER CANCELLED -> RESTORE INVENTORY + LOG ADJUSTMENT
-- =========================================================

CREATE TRIGGER trg_restore_inventory_on_cancellation
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF OLD.status <> 'CANCELLED'
       AND NEW.status = 'CANCELLED' THEN

        UPDATE inventory i
        JOIN order_item oi
            ON i.variant_id = oi.variant_id
        SET i.quantity = i.quantity + oi.quantity
        WHERE oi.order_id = NEW.order_id;

        INSERT INTO inventory_transaction (
            inventory_id, transaction_type, quantity, reference_type, reference_id
        )
        SELECT
            i.inventory_id, 'ADJUSTMENT', oi.quantity, 'ORDER_CANCELLED', NEW.order_id
        FROM order_item oi
        JOIN inventory i
            ON i.variant_id = oi.variant_id
        WHERE oi.order_id = NEW.order_id;

    END IF;
END//


-- =========================================================
-- 4. ORDER STATUS CHANGE -> STATUS HISTORY
-- =========================================================

CREATE TRIGGER trg_order_status_history
AFTER UPDATE ON orders
FOR EACH ROW
BEGIN
    IF OLD.status <> NEW.status THEN

        INSERT INTO order_status_history (
            order_id,
            old_status,
            new_status
        )
        VALUES (
            NEW.order_id,
            OLD.status,
            NEW.status
        );

    END IF;
END//

DELIMITER ;


-- =====================================================================
-- 4. TRIGGER DEMONSTRATION (uncomment to try; these change data)
-- =====================================================================

-- Over-ordering is blocked by trigger 1 (variant 10 has only 2 units):
-- INSERT INTO order_item (order_id, variant_id, quantity, unit_price)
-- VALUES (3, 10, 50, 6999.00);

-- Status change is logged by trigger 4:
-- UPDATE orders SET status = 'PROCESSING' WHERE order_id = 3;
-- SELECT * FROM order_status_history WHERE order_id = 3;

-- Cancellation restores stock via trigger 3:
-- UPDATE orders SET status = 'CANCELLED' WHERE order_id = 4;
-- SELECT * FROM inventory_transaction WHERE reference_type = 'ORDER_CANCELLED';
