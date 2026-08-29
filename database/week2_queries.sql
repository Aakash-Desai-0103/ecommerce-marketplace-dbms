-- =====================================================================
-- WEEK 2 — ecommerce-marketplace-dbms
-- Topics: DISTINCT, FROM, ORDER BY, HAVING, String comparison ops,
--         Set operations (UNION/INTERSECT/EXCEPT + ALL), Joins
--         (NATURAL/INNER/OUTER/CROSS), Nested queries
--
-- Column names follow the design in relational-schema.md / ER.txt.
-- If your actual schema.sql uses slightly different column names,
-- do a find-replace — the query logic/structure stays the same.
-- =====================================================================


-- =====================================================================
-- 1. DISTINCT
-- =====================================================================

-- Distinct list of product categories that currently have products
SELECT DISTINCT c.category_id, c.name
FROM CATEGORY c
JOIN PRODUCT_CATEGORY pc ON pc.category_id = c.category_id;

-- Distinct order statuses ever recorded
SELECT DISTINCT new_status
FROM ORDER_STATUS_HISTORY;

-- Distinct (brand, seller) pairs that have listed a product
SELECT DISTINCT p.brand_id, p.seller_id
FROM PRODUCT p;


-- =====================================================================
-- 2. FROM CLAUSE (multi-table, aliasing)
-- =====================================================================

-- Products with their brand and seller business name
SELECT
    p.product_id,
    p.name AS product_name,
    b.name AS brand_name,
    sp.business_name
FROM PRODUCT p, BRAND b, SELLER_PROFILE sp
WHERE p.brand_id = b.brand_id
  AND p.seller_id = sp.user_id;


-- =====================================================================
-- 3. ORDER BY
-- =====================================================================

-- Products, most expensive variant first
SELECT p.name, pv.price
FROM PRODUCT p
JOIN PRODUCT_VARIANT pv ON pv.product_id = p.product_id
ORDER BY pv.price DESC;

-- Users ordered by role, then by name
SELECT user_id, name, role
FROM USERS
ORDER BY role ASC, name ASC;

-- Reviews ordered by rating desc, then most recent first
SELECT review_id, product_id, rating, created_at
FROM REVIEW
ORDER BY rating DESC, created_at DESC;


-- =====================================================================
-- 4. HAVING
-- =====================================================================

-- Products with more than 5 reviews and average rating >= 4
SELECT
    r.product_id,
    COUNT(*)        AS total_reviews,
    AVG(r.rating)   AS avg_rating
FROM REVIEW r
GROUP BY r.product_id
HAVING COUNT(*) > 5 AND AVG(r.rating) >= 4;

-- Sellers whose total number of listed products exceeds 10
SELECT p.seller_id, COUNT(*) AS product_count
FROM PRODUCT p
GROUP BY p.seller_id
HAVING COUNT(*) > 10;

-- Customers who have placed orders totaling more than 50000
SELECT o.user_id, SUM(o.total_amount) AS lifetime_spend
FROM ORDERS o
GROUP BY o.user_id
HAVING SUM(o.total_amount) > 50000;


-- =====================================================================
-- 5. STRING COMPARISON OPERATIONS
-- =====================================================================

-- LIKE — products whose name starts with "iPhone"
SELECT product_id, name FROM PRODUCT WHERE name LIKE 'iPhone%';

-- LIKE with wildcard anywhere — emails from gmail
SELECT user_id, email FROM USERS WHERE email LIKE '%@gmail.com';

-- NOT LIKE
SELECT product_id, name FROM PRODUCT WHERE name NOT LIKE '%Refurbished%';

-- Exact string comparison
SELECT * FROM USERS WHERE role = 'SELLER';

-- String range comparison (lexicographic)
SELECT name FROM PRODUCT WHERE name BETWEEN 'A' AND 'M';

-- REGEXP — product names containing a digit (e.g. model numbers)
SELECT product_id, name FROM PRODUCT WHERE name REGEXP '[0-9]';

-- Case-insensitive-safe comparison using LOWER()
SELECT * FROM CATEGORY WHERE LOWER(name) = LOWER('electronics');


-- =====================================================================
-- 6. SET OPERATIONS — UNION / INTERSECT / EXCEPT (+ ALL variants)
-- Requires MySQL 8.0.31+ for native INTERSECT/EXCEPT.
-- =====================================================================

-- UNION — all user_ids who are either a seller or have placed an order
-- (duplicates removed)
SELECT user_id FROM SELLER_PROFILE
UNION
SELECT user_id FROM ORDERS;

-- UNION ALL — same as above but keep duplicates (faster, no dedup)
SELECT user_id FROM SELLER_PROFILE
UNION ALL
SELECT user_id FROM ORDERS;

-- INTERSECT — user_ids who are BOTH a seller AND a buyer (placed an order)
SELECT user_id FROM SELLER_PROFILE
INTERSECT
SELECT user_id FROM ORDERS;

-- INTERSECT ALL — same, keeping duplicate matches
SELECT user_id FROM SELLER_PROFILE
INTERSECT ALL
SELECT user_id FROM ORDERS;

-- EXCEPT — sellers who have NEVER placed an order as a buyer
SELECT user_id FROM SELLER_PROFILE
EXCEPT
SELECT user_id FROM ORDERS;

-- EXCEPT ALL — same, preserving multiplicity
SELECT user_id FROM SELLER_PROFILE
EXCEPT ALL
SELECT user_id FROM ORDERS;

-- ---------------------------------------------------------------------
-- Fallback if MySQL version < 8.0.31 (no native INTERSECT/EXCEPT):
--
-- INTERSECT equivalent:
-- SELECT user_id FROM SELLER_PROFILE
-- WHERE user_id IN (SELECT user_id FROM ORDERS);
--
-- EXCEPT equivalent:
-- SELECT user_id FROM SELLER_PROFILE
-- WHERE user_id NOT IN (SELECT user_id FROM ORDERS);
-- ---------------------------------------------------------------------


-- =====================================================================
-- 7. JOINS — NATURAL / INNER / OUTER / CROSS
-- =====================================================================

-- 7.1 INNER JOIN — orders with the customer who placed them
SELECT o.order_id, u.name, o.total_amount, o.status
FROM ORDERS o
INNER JOIN USERS u ON u.user_id = o.user_id;

-- 7.2 INNER JOIN (multi-table) — order items with product & variant info
SELECT oi.order_id, p.name AS product_name, pv.price, oi.quantity
FROM ORDER_ITEM oi
INNER JOIN PRODUCT_VARIANT pv ON pv.variant_id = oi.variant_id
INNER JOIN PRODUCT p          ON p.product_id  = pv.product_id;

-- 7.3 NATURAL JOIN — works because both tables share the same FK column
-- name (user_id). Use only when column names truly match your schema.
SELECT *
FROM USERS
NATURAL JOIN ADDRESS;

-- 7.4 LEFT OUTER JOIN — every seller, with product count (0 if none)
SELECT sp.user_id, sp.business_name, COUNT(p.product_id) AS product_count
FROM SELLER_PROFILE sp
LEFT OUTER JOIN PRODUCT p ON p.seller_id = sp.user_id
GROUP BY sp.user_id, sp.business_name;

-- 7.5 RIGHT OUTER JOIN — every product, with its category even if
-- somehow uncategorized (kept here to demonstrate RIGHT JOIN syntax)
SELECT p.name, c.name AS category_name
FROM PRODUCT_CATEGORY pc
RIGHT OUTER JOIN PRODUCT p ON p.product_id = pc.product_id
LEFT OUTER JOIN CATEGORY c  ON c.category_id = pc.category_id;

-- 7.6 FULL OUTER JOIN — MySQL has no native FULL OUTER JOIN.
-- Simulated using LEFT JOIN UNION RIGHT JOIN:
-- all users and all addresses, matched where possible
SELECT u.user_id, u.name, a.address_id, a.city
FROM USERS u
LEFT JOIN ADDRESS a ON a.user_id = u.user_id
UNION
SELECT u.user_id, u.name, a.address_id, a.city
FROM USERS u
RIGHT JOIN ADDRESS a ON a.user_id = u.user_id;

-- 7.7 CROSS JOIN — every attribute combined with every attribute value
-- (typically filtered further; shown here to demonstrate a Cartesian product)
SELECT a.name AS attribute, av.value
FROM ATTRIBUTE a
CROSS JOIN ATTRIBUTE_VALUE av
LIMIT 50;

-- 7.8 SELF JOIN via CROSS JOIN example — products from the same category
-- paired together (excluding a product pairing with itself)
SELECT p1.name AS product_a, p2.name AS product_b, pc1.category_id
FROM PRODUCT_CATEGORY pc1
JOIN PRODUCT_CATEGORY pc2 ON pc1.category_id = pc2.category_id
                          AND pc1.product_id < pc2.product_id
JOIN PRODUCT p1 ON p1.product_id = pc1.product_id
JOIN PRODUCT p2 ON p2.product_id = pc2.product_id;


-- =====================================================================
-- 8. NESTED QUERIES (SUBQUERIES)
-- =====================================================================

-- 8.1 Subquery in WHERE with IN — users who have written at least one review
SELECT user_id, name
FROM USERS
WHERE user_id IN (SELECT DISTINCT user_id FROM REVIEW);

-- 8.2 Subquery in WHERE with NOT IN — products that have never been ordered
SELECT product_id, name
FROM PRODUCT
WHERE product_id NOT IN (
    SELECT DISTINCT pv.product_id
    FROM ORDER_ITEM oi
    JOIN PRODUCT_VARIANT pv ON pv.variant_id = oi.variant_id
);

-- 8.3 Correlated subquery with EXISTS — sellers who have at least one
-- product priced above 10000
SELECT sp.user_id, sp.business_name
FROM SELLER_PROFILE sp
WHERE EXISTS (
    SELECT 1
    FROM PRODUCT p
    JOIN PRODUCT_VARIANT pv ON pv.product_id = p.product_id
    WHERE p.seller_id = sp.user_id
      AND pv.price > 10000
);

-- 8.4 Correlated subquery with NOT EXISTS — customers who have never
-- placed an order
SELECT u.user_id, u.name
FROM USERS u
WHERE u.role = 'CUSTOMER'
  AND NOT EXISTS (
      SELECT 1 FROM ORDERS o WHERE o.user_id = u.user_id
  );

-- 8.5 Scalar subquery in SELECT — each product with its average rating
SELECT
    p.product_id,
    p.name,
    (SELECT AVG(r.rating) FROM REVIEW r WHERE r.product_id = p.product_id) AS avg_rating
FROM PRODUCT p;

-- 8.6 Subquery with ANY — variants priced higher than ANY variant in
-- category 'Accessories' (i.e. higher than the cheapest one)
SELECT pv.variant_id, pv.price
FROM PRODUCT_VARIANT pv
WHERE pv.price > ANY (
    SELECT pv2.price
    FROM PRODUCT_VARIANT pv2
    JOIN PRODUCT p2          ON p2.product_id = pv2.product_id
    JOIN PRODUCT_CATEGORY pc ON pc.product_id = p2.product_id
    JOIN CATEGORY c          ON c.category_id = pc.category_id
    WHERE c.name = 'Accessories'
);

-- 8.7 Subquery with ALL — variants priced higher than ALL variants in
-- category 'Accessories' (i.e. higher than the most expensive one)
SELECT pv.variant_id, pv.price
FROM PRODUCT_VARIANT pv
WHERE pv.price > ALL (
    SELECT pv2.price
    FROM PRODUCT_VARIANT pv2
    JOIN PRODUCT p2          ON p2.product_id = pv2.product_id
    JOIN PRODUCT_CATEGORY pc ON pc.product_id = p2.product_id
    JOIN CATEGORY c          ON c.category_id = pc.category_id
    WHERE c.name = 'Accessories'
);

-- 8.8 Subquery in FROM (derived table) — top spending customers
SELECT ranked.user_id, ranked.total_spent
FROM (
    SELECT user_id, SUM(total_amount) AS total_spent
    FROM ORDERS
    GROUP BY user_id
) AS ranked
WHERE ranked.total_spent > 20000
ORDER BY ranked.total_spent DESC;

-- 8.9 Nested correlated subquery — order items priced above the average
-- price of items within the same order (identifying the "expensive" item
-- per order)
SELECT oi.order_item_id, oi.order_id, oi.unit_price
FROM ORDER_ITEM oi
WHERE oi.unit_price > (
    SELECT AVG(oi2.unit_price)
    FROM ORDER_ITEM oi2
    WHERE oi2.order_id = oi.order_id
);
