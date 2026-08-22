USE ecommerce_marketplace;

-- ============================================================
-- BASIC SELECT
-- ============================================================

-- 1. Display all products
SELECT * FROM product;

-- 2. Display active products
SELECT product_id, name, status
FROM product
WHERE status = 'ACTIVE';

-- 3. Products costing more than ₹50,000
SELECT name, price
FROM product_variant pv
JOIN product p ON pv.product_id = p.product_id
WHERE price > 50000;


-- ============================================================
-- INSERT
-- ============================================================

INSERT INTO brand (name)
VALUES ('Sony');


-- ============================================================
-- UPDATE
-- ============================================================

UPDATE product_variant
SET price = price * 1.05
WHERE variant_id = 1;


-- ============================================================
-- DELETE
-- ============================================================

DELETE FROM brand
WHERE name = 'Sony';


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
JOIN product p ON pv.product_id = p.product_id;


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
    AVG(r.rating) AS average_rating
FROM product p
JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.name;


-- 8. Total sales by product
SELECT
    p.name,
    SUM(oi.quantity * oi.unit_price) AS total_sales
FROM product p
JOIN product_variant pv ON p.product_id = pv.product_id
JOIN order_item oi ON pv.variant_id = oi.variant_id
GROUP BY p.product_id, p.name;


-- ============================================================
-- HAVING
-- ============================================================

-- 9. Products whose average rating is >= 4
SELECT
    p.name,
    AVG(r.rating) AS average_rating
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
