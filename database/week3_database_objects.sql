USE ecommerce_marketplace;

-- =====================================================================
-- WEEK 3 — DATABASE OBJECTS
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
FROM PRODUCT p
JOIN SELLER_PROFILE sp
    ON sp.user_id = p.seller_id
JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
JOIN INVENTORY i
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
FROM USERS u
JOIN ORDERS o
    ON o.user_id = u.user_id;


-- 1.3 Seller sales summary view
CREATE OR REPLACE VIEW vw_seller_sales_summary AS
SELECT
    sp.user_id AS seller_id,
    sp.store_name,
    COUNT(DISTINCT p.product_id) AS total_products,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    COALESCE(SUM(oi.quantity * oi.unit_price), 0) AS total_revenue
FROM SELLER_PROFILE sp
LEFT JOIN PRODUCT p
    ON p.seller_id = sp.user_id
LEFT JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
LEFT JOIN ORDER_ITEM oi
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
FROM PRODUCT p
JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
JOIN INVENTORY i
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

-- Remove previously created demonstration users
DROP USER IF EXISTS 'marketplace_viewer'@'localhost';
DROP USER IF EXISTS 'marketplace_manager_user'@'localhost';

-- Remove previously created roles
DROP ROLE IF EXISTS marketplace_readonly;
DROP ROLE IF EXISTS marketplace_manager;


-- ---------------------------------------------------------------------
-- CREATE DATABASE ROLES
-- ---------------------------------------------------------------------

CREATE ROLE IF NOT EXISTS marketplace_customer;
CREATE ROLE IF NOT EXISTS marketplace_seller;
CREATE ROLE IF NOT EXISTS marketplace_admin;


-- ---------------------------------------------------------------------
-- CUSTOMER ROLE
-- Customers can browse products and perform order-related operations.
-- ---------------------------------------------------------------------

GRANT SELECT
ON ecommerce_marketplace.PRODUCT
TO marketplace_customer;

GRANT SELECT
ON ecommerce_marketplace.PRODUCT_VARIANT
TO marketplace_customer;

GRANT SELECT
ON ecommerce_marketplace.INVENTORY
TO marketplace_customer;

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.ORDERS
TO marketplace_customer;

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.ORDER_ITEM
TO marketplace_customer;

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.REVIEW
TO marketplace_customer;


-- ---------------------------------------------------------------------
-- SELLER ROLE
-- Sellers can manage products, variants and inventory.
-- ---------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.PRODUCT
TO marketplace_seller;

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.PRODUCT_VARIANT
TO marketplace_seller;

GRANT SELECT, INSERT, UPDATE
ON ecommerce_marketplace.INVENTORY
TO marketplace_seller;

GRANT SELECT
ON ecommerce_marketplace.ORDERS
TO marketplace_seller;

GRANT SELECT
ON ecommerce_marketplace.ORDER_ITEM
TO marketplace_seller;

GRANT SELECT
ON ecommerce_marketplace.REVIEW
TO marketplace_seller;


-- ---------------------------------------------------------------------
-- ADMIN ROLE
-- Administrator has full access to the project database.
-- ---------------------------------------------------------------------

GRANT ALL PRIVILEGES
ON ecommerce_marketplace.*
TO marketplace_admin;


-- ---------------------------------------------------------------------
-- CREATE DEMONSTRATION DATABASE USERS
-- ---------------------------------------------------------------------

CREATE USER IF NOT EXISTS 'customer_user'@'localhost'
IDENTIFIED BY 'Customer@123';

CREATE USER IF NOT EXISTS 'seller_user'@'localhost'
IDENTIFIED BY 'Seller@123';

CREATE USER IF NOT EXISTS 'admin_user'@'localhost'
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

SHOW GRANTS FOR 'customer_user'@'localhost';

SHOW GRANTS FOR 'seller_user'@'localhost';

SHOW GRANTS FOR 'admin_user'@'localhost';

USE ecommerce_marketplace;

-- =========================================================
-- TRIGGERS
-- =========================================================

-- Supporting table: Order Status History
CREATE TABLE IF NOT EXISTS order_status_history (
    history_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT UNSIGNED NOT NULL,
    old_status ENUM(
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'SHIPPED',
        'DELIVERED',
        'CANCELLED',
        'RETURNED'
    ),
    new_status ENUM(
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'SHIPPED',
        'DELIVERED',
        'CANCELLED',
        'RETURNED'
    ) NOT NULL,
    changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE
);


-- Supporting table: Low Stock Notifications
CREATE TABLE IF NOT EXISTS low_stock_notification (
    notification_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    variant_id BIGINT UNSIGNED NOT NULL,
    current_quantity INT UNSIGNED NOT NULL,
    reorder_level INT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id)
        ON DELETE CASCADE
);


DELIMITER //

-- =========================================================
-- 1. ORDER ITEM ADDED -> REDUCE INVENTORY
-- =========================================================

CREATE TRIGGER trg_reduce_inventory
AFTER INSERT ON order_item
FOR EACH ROW
BEGIN
    UPDATE inventory
    SET quantity = quantity - NEW.quantity
    WHERE variant_id = NEW.variant_id;
END//


-- =========================================================
-- 2. ORDER CANCELLED -> RESTORE INVENTORY
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

    END IF;
END//


-- =========================================================
-- 3. ORDER STATUS CHANGE -> STATUS HISTORY
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


-- =========================================================
-- 4. LOW STOCK -> CREATE NOTIFICATION
-- =========================================================

CREATE TRIGGER trg_low_stock_notification
AFTER UPDATE ON inventory
FOR EACH ROW
BEGIN
    IF NEW.quantity <= NEW.reorder_level
       AND OLD.quantity > OLD.reorder_level THEN

        INSERT INTO low_stock_notification (
            variant_id,
            current_quantity,
            reorder_level
        )
        VALUES (
            NEW.variant_id,
            NEW.quantity,
            NEW.reorder_level
        );

    END IF;
END//

DELIMITER ;