USE ecommerce_marketplace;

-- =====================================================================
-- WEEK 3 — CORRELATED QUERIES AND ADDITIONAL NESTED QUERIES
-- =====================================================================


-- =====================================================================
-- 1. CORRELATED QUERIES
-- =====================================================================

-- 1.1 Variants priced above the average variant price
-- of the same product
SELECT
    p.product_id,
    p.name AS product_name,
    pv.variant_id,
    pv.price
FROM PRODUCT p
JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
WHERE pv.price > (
    SELECT AVG(pv2.price)
    FROM PRODUCT_VARIANT pv2
    WHERE pv2.product_id = p.product_id
);


-- 1.2 Products whose average rating is above the
-- overall average rating
SELECT
    p.product_id,
    p.name AS product_name,
    (
        SELECT AVG(r.rating)
        FROM REVIEW r
        WHERE r.product_id = p.product_id
    ) AS product_avg_rating
FROM PRODUCT p
WHERE (
    SELECT AVG(r.rating)
    FROM REVIEW r
    WHERE r.product_id = p.product_id
) > (
    SELECT AVG(rating)
    FROM REVIEW
);


-- 1.3 Customers who have placed an order above
-- their own average order value
SELECT
    u.user_id,
    u.name,
    o.order_id,
    o.total_amount
FROM USERS u
JOIN ORDERS o
    ON o.user_id = u.user_id
WHERE o.total_amount > (
    SELECT AVG(o2.total_amount)
    FROM ORDERS o2
    WHERE o2.user_id = u.user_id
);


-- 1.4 Products having more variants than the average
-- number of variants for that seller's products
SELECT
    p.product_id,
    p.seller_id,
    p.name AS product_name
FROM PRODUCT p
WHERE (
    SELECT COUNT(*)
    FROM PRODUCT_VARIANT pv
    WHERE pv.product_id = p.product_id
) > (
    SELECT AVG(variant_count)
    FROM (
        SELECT COUNT(*) AS variant_count
        FROM PRODUCT p2
        JOIN PRODUCT_VARIANT pv2
            ON pv2.product_id = p2.product_id
        WHERE p2.seller_id = p.seller_id
        GROUP BY p2.product_id
    ) AS seller_product_variants
);


-- 1.5 Products having at least one variant with stock
-- below the average stock of variants of that product
SELECT DISTINCT
    p.product_id,
    p.name AS product_name
FROM PRODUCT p
JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
JOIN INVENTORY i
    ON i.variant_id = pv.variant_id
WHERE i.quantity < (
    SELECT AVG(i2.quantity)
    FROM PRODUCT_VARIANT pv2
    JOIN INVENTORY i2
        ON i2.variant_id = pv2.variant_id
    WHERE pv2.product_id = p.product_id
);


-- =====================================================================
-- 2. ADDITIONAL NESTED QUERIES
-- =====================================================================

-- 2.1 Products belonging to categories containing more
-- than the average number of products per category
SELECT DISTINCT
    p.product_id,
    p.name AS product_name
FROM PRODUCT p
JOIN PRODUCT_CATEGORY pc
    ON pc.product_id = p.product_id
WHERE pc.category_id IN (
    SELECT category_id
    FROM PRODUCT_CATEGORY
    GROUP BY category_id
    HAVING COUNT(*) > (
        SELECT AVG(product_count)
        FROM (
            SELECT COUNT(*) AS product_count
            FROM PRODUCT_CATEGORY
            GROUP BY category_id
        ) AS category_counts
    )
);


-- 2.2 Customers who have placed an order containing
-- a product with an average rating of 4 or above
SELECT DISTINCT
    u.user_id,
    u.name
FROM USERS u
WHERE u.user_id IN (
    SELECT o.user_id
    FROM ORDERS o
    WHERE o.order_id IN (
        SELECT oi.order_id
        FROM ORDER_ITEM oi
        WHERE oi.variant_id IN (
            SELECT pv.variant_id
            FROM PRODUCT_VARIANT pv
            WHERE pv.product_id IN (
                SELECT r.product_id
                FROM REVIEW r
                GROUP BY r.product_id
                HAVING AVG(r.rating) >= 4
            )
        )
    )
);


-- 2.3 Sellers who have sold products belonging to
-- categories containing more than one product
SELECT DISTINCT
    sp.user_id,
    sp.store_name
FROM SELLER_PROFILE sp
WHERE sp.user_id IN (
    SELECT p.seller_id
    FROM PRODUCT p
    WHERE p.product_id IN (
        SELECT pv.product_id
        FROM PRODUCT_VARIANT pv
        WHERE pv.variant_id IN (
            SELECT oi.variant_id
            FROM ORDER_ITEM oi
        )
    )
    AND p.product_id IN (
        SELECT pc.product_id
        FROM PRODUCT_CATEGORY pc
        WHERE pc.category_id IN (
            SELECT pc2.category_id
            FROM PRODUCT_CATEGORY pc2
            GROUP BY pc2.category_id
            HAVING COUNT(*) > 1
        )
    )
);


-- 2.4 Products whose total quantity sold is greater than
-- the average quantity sold across all ordered products
SELECT
    p.product_id,
    p.name AS product_name,
    SUM(oi.quantity) AS total_quantity_sold
FROM PRODUCT p
JOIN PRODUCT_VARIANT pv
    ON pv.product_id = p.product_id
JOIN ORDER_ITEM oi
    ON oi.variant_id = pv.variant_id
GROUP BY p.product_id, p.name
HAVING SUM(oi.quantity) > (
    SELECT AVG(total_quantity)
    FROM (
        SELECT
            SUM(oi2.quantity) AS total_quantity
        FROM PRODUCT_VARIANT pv2
        JOIN ORDER_ITEM oi2
            ON oi2.variant_id = pv2.variant_id
        GROUP BY pv2.product_id
    ) AS product_sales
);


-- 2.5 Customers whose total spending is greater than
-- the average spending of customers who placed orders
SELECT
    u.user_id,
    u.name,
    SUM(o.total_amount) AS total_spent
FROM USERS u
JOIN ORDERS o
    ON o.user_id = u.user_id
GROUP BY u.user_id, u.name
HAVING SUM(o.total_amount) > (
    SELECT AVG(customer_total)
    FROM (
        SELECT
            SUM(total_amount) AS customer_total
        FROM ORDERS
        GROUP BY user_id
    ) AS customer_spending
);