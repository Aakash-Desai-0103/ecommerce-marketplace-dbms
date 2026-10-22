USE ecommerce_marketplace;

-- ============================================================
-- WEEK 1 — DDL, DML AND BASIC QUERIES
-- ============================================================


-- ============================================================
-- DDL: CREATE / ALTER / DROP
-- Uses a scratch table so the 28-table schema is left unchanged.
-- ============================================================

DROP TABLE IF EXISTS seller_announcement;

-- CREATE
CREATE TABLE seller_announcement (
    announcement_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    seller_id BIGINT UNSIGNED NOT NULL,
    title VARCHAR(100) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT fk_announcement_seller
        FOREIGN KEY (seller_id)
        REFERENCES seller_profile(user_id)
        ON DELETE CASCADE
);

-- ALTER: add a column, widen a column, add a CHECK constraint
ALTER TABLE seller_announcement
    ADD COLUMN body TEXT;

ALTER TABLE seller_announcement
    MODIFY COLUMN title VARCHAR(150) NOT NULL;

ALTER TABLE seller_announcement
    ADD CONSTRAINT chk_announcement_title
        CHECK (CHAR_LENGTH(title) >= 5);

-- CREATE / DROP INDEX
CREATE INDEX idx_announcement_created
    ON seller_announcement (created_at);

DESCRIBE seller_announcement;

DROP INDEX idx_announcement_created ON seller_announcement;

-- ALTER: drop a column
ALTER TABLE seller_announcement
    DROP COLUMN body;

-- DROP
DROP TABLE seller_announcement;


-- ============================================================
-- BASIC SELECT
-- ============================================================

-- 1. Display all products
SELECT * FROM product;

-- 2. Display active products
SELECT product_id, name, status
FROM product
WHERE status = 'ACTIVE';

-- 3. Variants costing more than ₹50,000
SELECT p.name, pv.sku, pv.price
FROM product_variant pv
JOIN product p ON pv.product_id = p.product_id
WHERE pv.price > 50000;


-- ============================================================
-- INSERT
-- ============================================================

INSERT INTO brand (name)
VALUES ('Sony');


-- ============================================================
-- UPDATE
-- Price change after launch. Past order_item.unit_price values
-- are unaffected, which is why the price is copied into order_item.
-- ============================================================

UPDATE product_variant
SET price = 72999.00
WHERE sku = 'IPH16-128-BLK';

UPDATE brand
SET name = 'Sony India'
WHERE name = 'Sony';


-- ============================================================
-- DELETE
-- ============================================================

DELETE FROM brand
WHERE name = 'Sony India';


-- ============================================================
-- CONSTRAINT CHECKS (each statement below is rejected by MySQL)
-- Uncomment one at a time to demonstrate database-level validation.
-- ============================================================

-- Duplicate email (UNIQUE):
-- INSERT INTO users (name, email, password_hash, role)
-- VALUES ('Copy', 'aarav@example.com', 'x', 'CUSTOMER');

-- Rating outside 1-5 (CHECK):
-- INSERT INTO review (user_id, product_id, rating) VALUES (2, 1, 6);

-- Negative price (CHECK):
-- UPDATE product_variant SET price = -1 WHERE variant_id = 1;

-- Non-existent seller (FOREIGN KEY):
-- INSERT INTO product (seller_id, brand_id, name) VALUES (999, 1, 'Ghost');

-- Invalid role (ENUM):
-- INSERT INTO users (name, email, password_hash, role)
-- VALUES ('X', 'x@example.com', 'x', 'MANAGER');


-- ============================================================
-- JOINS
-- ============================================================

-- 4. Products with their sellers and brands
SELECT
    p.name AS product,
    sp.store_name AS seller,
    b.name AS brand
FROM product p
JOIN seller_profile sp
    ON p.seller_id = sp.user_id
JOIN brand b
    ON p.brand_id = b.brand_id;


-- 5. Orders with customer and product
SELECT
    o.order_id,
    u.name AS customer,
    p.name AS product,
    oi.quantity,
    oi.unit_price
FROM orders o
JOIN users u ON o.user_id = u.user_id
JOIN order_item oi ON o.order_id = oi.order_id
JOIN product_variant pv ON oi.variant_id = pv.variant_id
JOIN product p ON pv.product_id = p.product_id
ORDER BY o.order_id;


-- ============================================================
-- AGGREGATION / GROUP BY
-- ============================================================

-- 6. Number of products per seller
SELECT
    sp.store_name,
    COUNT(p.product_id) AS product_count
FROM seller_profile sp
LEFT JOIN product p
    ON sp.user_id = p.seller_id
GROUP BY sp.user_id, sp.store_name;


-- 7. Average product rating
SELECT
    p.name,
    ROUND(AVG(r.rating), 2) AS average_rating
FROM product p
JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.name;


-- 8. Total sales by product (cancelled orders excluded)
SELECT
    p.name,
    SUM(oi.quantity * oi.unit_price) AS total_sales
FROM product p
JOIN product_variant pv ON p.product_id = pv.product_id
JOIN order_item oi ON pv.variant_id = oi.variant_id
JOIN orders o ON o.order_id = oi.order_id
WHERE o.status <> 'CANCELLED'
GROUP BY p.product_id, p.name;


-- ============================================================
-- HAVING
-- ============================================================

-- 9. Products whose average rating is >= 4
SELECT
    p.name,
    ROUND(AVG(r.rating), 2) AS average_rating
FROM product p
JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.name
HAVING AVG(r.rating) >= 4;


-- ============================================================
-- RELATIONAL ALGEBRA EQUIVALENT
-- ============================================================

-- Selection:
-- σ status='ACTIVE'(PRODUCT)

SELECT *
FROM product
WHERE status = 'ACTIVE';

-- Projection:
-- π name, description(PRODUCT)

SELECT name, description
FROM product;


-- Selection + Projection:
-- π name(σ status='ACTIVE'(PRODUCT))

SELECT name
FROM product
WHERE status = 'ACTIVE';


-- Rename (ρ):
-- ρ seller(store, business)(π store_name, business_name(SELLER_PROFILE))

SELECT store_name AS store, business_name AS business
FROM seller_profile AS seller;


-- Cartesian product (×):
-- BRAND × CATEGORY  (every brand paired with every category: 6 x 7 = 42 rows)

SELECT b.name AS brand, c.name AS category
FROM brand b, category c;


-- Theta join (⋈θ) = selection over a cartesian product:
-- σ PRODUCT.brand_id = BRAND.brand_id (PRODUCT × BRAND)

SELECT p.name AS product, b.name AS brand
FROM product p, brand b
WHERE p.brand_id = b.brand_id;


-- Natural join (⋈) on the common attribute user_id:
-- π user_id, name, store_name (USERS ⋈ SELLER_PROFILE)

SELECT user_id, name, store_name
FROM users
NATURAL JOIN seller_profile;


-- Union (∪): users who are sellers OR have written a review
-- π user_id(SELLER_PROFILE) ∪ π user_id(REVIEW)

SELECT user_id FROM seller_profile
UNION
SELECT user_id FROM review;


-- Intersection (∩): customers who placed an order AND wrote a review
-- π user_id(ORDERS) ∩ π user_id(REVIEW)

SELECT user_id FROM orders
INTERSECT
SELECT user_id FROM review;


-- Set difference (−): customers who placed an order but never wrote a review
-- π user_id(ORDERS) − π user_id(REVIEW)

SELECT user_id FROM orders
EXCEPT
SELECT user_id FROM review;


-- Division (÷): customers who bought products from EVERY category in
-- the set {Electronics, Footwear}
-- π user_id, category(ORDERS ⋈ ORDER_ITEM ⋈ PRODUCT_VARIANT ⋈ PRODUCT_CATEGORY ⋈ CATEGORY)
--     ÷ π name(σ name ∈ {Electronics, Footwear}(CATEGORY))
-- SQL has no ÷ operator; it is written as a double NOT EXISTS:
-- "there is no required category this customer has not bought from".

SELECT u.user_id, u.name
FROM users u
WHERE u.role = 'CUSTOMER'
  AND NOT EXISTS (
      SELECT 1
      FROM category c
      WHERE c.name IN ('Electronics', 'Footwear')
        AND NOT EXISTS (
            SELECT 1
            FROM orders o
            JOIN order_item oi        ON oi.order_id = o.order_id
            JOIN product_variant pv   ON pv.variant_id = oi.variant_id
            JOIN product_category pc  ON pc.product_id = pv.product_id
            WHERE o.user_id = u.user_id
              AND pc.category_id = c.category_id
        )
  );


-- Aggregate with grouping (γ):
-- seller_id γ COUNT(product_id) → product_count (PRODUCT)

SELECT seller_id, COUNT(product_id) AS product_count
FROM product
GROUP BY seller_id;
