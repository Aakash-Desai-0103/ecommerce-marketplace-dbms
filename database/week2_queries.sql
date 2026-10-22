USE ecommerce_marketplace;

-- =====================================================================
-- WEEK 2 — ecommerce-marketplace-dbms
-- Topics: DISTINCT, FROM, ORDER BY, HAVING, String comparison ops,
--         Set operations (UNION/INTERSECT/EXCEPT + ALL), Joins
--         (NATURAL/INNER/OUTER/CROSS), Nested queries
-- =====================================================================


-- =====================================================================
-- 1. DISTINCT
-- =====================================================================

-- Distinct list of product categories that currently have products
SELECT DISTINCT c.category_id, c.name
FROM category c
JOIN product_category pc ON pc.category_id = c.category_id;

-- Distinct order statuses ever recorded
SELECT DISTINCT new_status
FROM order_status_history;

-- Distinct (brand, seller) pairs that have listed a product
SELECT DISTINCT p.brand_id, p.seller_id
FROM product p;


-- =====================================================================
-- 2. FROM CLAUSE (multi-table, aliasing)
-- =====================================================================

-- Products with their brand and seller business name
SELECT
    p.product_id,
    p.name AS product_name,
    b.name AS brand_name,
    sp.business_name
FROM product p, brand b, seller_profile sp
WHERE p.brand_id = b.brand_id
  AND p.seller_id = sp.user_id;


-- =====================================================================
-- 3. ORDER BY
-- =====================================================================

-- Products, most expensive variant first
SELECT p.name, pv.price
FROM product p
JOIN product_variant pv ON pv.product_id = p.product_id
ORDER BY pv.price DESC;

-- Users ordered by role, then by name
SELECT user_id, name, role
FROM users
ORDER BY role ASC, name ASC;

-- Reviews ordered by rating desc, then most recent first
SELECT review_id, product_id, rating, created_at
FROM review
ORDER BY rating DESC, created_at DESC;


-- =====================================================================
-- 4. HAVING
-- =====================================================================

-- Products with at least one review and an average rating >= 4
SELECT
    r.product_id,
    COUNT(*)                 AS total_reviews,
    ROUND(AVG(r.rating), 2)  AS avg_rating
FROM review r
GROUP BY r.product_id
HAVING COUNT(*) >= 1 AND AVG(r.rating) >= 4;

-- Sellers listing more than 2 products
SELECT p.seller_id, COUNT(*) AS product_count
FROM product p
GROUP BY p.seller_id
HAVING COUNT(*) > 2;

-- Customers whose non-cancelled orders total more than 50000
SELECT o.user_id, SUM(o.total_amount) AS lifetime_spend
FROM orders o
WHERE o.status <> 'CANCELLED'
GROUP BY o.user_id
HAVING SUM(o.total_amount) > 50000;


-- =====================================================================
-- 5. STRING COMPARISON OPERATIONS
-- =====================================================================

-- LIKE — products whose name starts with "iPhone"
SELECT product_id, name FROM product WHERE name LIKE 'iPhone%';

-- LIKE with wildcard anywhere — store accounts by email
SELECT user_id, email FROM users WHERE email LIKE '%store%' OR name LIKE '%Store';

-- NOT LIKE
SELECT product_id, name FROM product WHERE name NOT LIKE '%Refurbished%';

-- Exact string comparison (password_hash deliberately not selected)
SELECT user_id, name, email, role FROM users WHERE role = 'SELLER';

-- String range comparison (lexicographic)
SELECT name FROM product WHERE name BETWEEN 'A' AND 'M';

-- REGEXP — product names containing a digit (e.g. model numbers)
SELECT product_id, name FROM product WHERE name REGEXP '[0-9]';

-- Case-insensitive-safe comparison using LOWER()
SELECT * FROM category WHERE LOWER(name) = LOWER('electronics');


-- =====================================================================
-- 6. SET OPERATIONS — UNION / INTERSECT / EXCEPT (+ ALL variants)
-- Requires MySQL 8.0.31+ for native INTERSECT/EXCEPT.
-- =====================================================================

-- UNION — all user_ids who are either a seller or have placed an order
-- (duplicates removed)
SELECT user_id FROM seller_profile
UNION
SELECT user_id FROM orders;

-- UNION ALL — same as above but keep duplicates (faster, no dedup)
SELECT user_id FROM seller_profile
UNION ALL
SELECT user_id FROM orders;

-- INTERSECT — user_ids who are BOTH a seller AND a buyer (placed an order)
SELECT user_id FROM seller_profile
INTERSECT
SELECT user_id FROM orders;

-- INTERSECT ALL — same, keeping duplicate matches
SELECT user_id FROM seller_profile
INTERSECT ALL
SELECT user_id FROM orders;

-- EXCEPT — sellers who have NEVER placed an order as a buyer
SELECT user_id FROM seller_profile
EXCEPT
SELECT user_id FROM orders;

-- EXCEPT ALL — same, preserving multiplicity
SELECT user_id FROM seller_profile
EXCEPT ALL
SELECT user_id FROM orders;

-- ---------------------------------------------------------------------
-- Fallback if MySQL version < 8.0.31 (no native INTERSECT/EXCEPT):
--
-- INTERSECT equivalent:
-- SELECT user_id FROM seller_profile
-- WHERE user_id IN (SELECT user_id FROM orders);
--
-- EXCEPT equivalent:
-- SELECT user_id FROM seller_profile
-- WHERE user_id NOT IN (SELECT user_id FROM orders);
-- ---------------------------------------------------------------------


-- =====================================================================
-- 7. JOINS — NATURAL / INNER / OUTER / CROSS
-- =====================================================================

-- 7.1 INNER JOIN — orders with the customer who placed them
SELECT o.order_id, u.name, o.total_amount, o.status
FROM orders o
INNER JOIN users u ON u.user_id = o.user_id;

-- 7.2 INNER JOIN (multi-table) — order items with product & variant info
SELECT oi.order_id, p.name AS product_name, pv.price, oi.quantity
FROM order_item oi
INNER JOIN product_variant pv ON pv.variant_id = oi.variant_id
INNER JOIN product p          ON p.product_id  = pv.product_id;

-- 7.3 NATURAL JOIN — works because both tables share the same FK column
-- name (user_id) and no other column name in common.
SELECT user_id, name, address_id, city, address_type
FROM users
NATURAL JOIN address;

-- 7.4 LEFT OUTER JOIN — every seller, with product count (0 if none)
SELECT sp.user_id, sp.business_name, COUNT(p.product_id) AS product_count
FROM seller_profile sp
LEFT OUTER JOIN product p ON p.seller_id = sp.user_id
GROUP BY sp.user_id, sp.business_name;

-- 7.5 RIGHT OUTER JOIN — every product, with its category even if
-- somehow uncategorized (kept here to demonstrate RIGHT JOIN syntax)
SELECT p.name, c.name AS category_name
FROM product_category pc
RIGHT OUTER JOIN product p ON p.product_id = pc.product_id
LEFT OUTER JOIN category c  ON c.category_id = pc.category_id;

-- 7.6 FULL OUTER JOIN — MySQL has no native FULL OUTER JOIN.
-- Simulated using LEFT JOIN UNION RIGHT JOIN:
-- all users and all addresses, matched where possible
SELECT u.user_id, u.name, a.address_id, a.city
FROM users u
LEFT JOIN address a ON a.user_id = u.user_id
UNION
SELECT u.user_id, u.name, a.address_id, a.city
FROM users u
RIGHT JOIN address a ON a.user_id = u.user_id;

-- 7.7 CROSS JOIN — every attribute combined with every attribute value
-- (typically filtered further; shown here to demonstrate a Cartesian product)
SELECT a.name AS attribute, av.value
FROM attribute a
CROSS JOIN attribute_value av
LIMIT 50;

-- 7.8 SELF JOIN via CROSS JOIN example — products from the same category
-- paired together (excluding a product pairing with itself)
SELECT p1.name AS product_a, p2.name AS product_b, pc1.category_id
FROM product_category pc1
JOIN product_category pc2 ON pc1.category_id = pc2.category_id
                          AND pc1.product_id < pc2.product_id
JOIN product p1 ON p1.product_id = pc1.product_id
JOIN product p2 ON p2.product_id = pc2.product_id;


-- =====================================================================
-- 8. NESTED QUERIES (SUBQUERIES)
-- =====================================================================

-- 8.1 Subquery in WHERE with IN — users who have written at least one review
SELECT user_id, name
FROM users
WHERE user_id IN (SELECT DISTINCT user_id FROM review);

-- 8.2 Subquery in WHERE with NOT IN — products that have never been ordered
SELECT product_id, name
FROM product
WHERE product_id NOT IN (
    SELECT DISTINCT pv.product_id
    FROM order_item oi
    JOIN product_variant pv ON pv.variant_id = oi.variant_id
);

-- 8.3 Correlated subquery with EXISTS — sellers who have at least one
-- product priced above 10000
SELECT sp.user_id, sp.business_name
FROM seller_profile sp
WHERE EXISTS (
    SELECT 1
    FROM product p
    JOIN product_variant pv ON pv.product_id = p.product_id
    WHERE p.seller_id = sp.user_id
      AND pv.price > 10000
);

-- 8.4 Correlated subquery with NOT EXISTS — customers who have never
-- placed an order
SELECT u.user_id, u.name
FROM users u
WHERE u.role = 'CUSTOMER'
  AND NOT EXISTS (
      SELECT 1 FROM orders o WHERE o.user_id = u.user_id
  );

-- 8.5 Scalar subquery in SELECT — each product with its average rating
SELECT
    p.product_id,
    p.name,
    (SELECT AVG(r.rating) FROM review r WHERE r.product_id = p.product_id) AS avg_rating
FROM product p;

-- 8.6 Subquery with ANY — variants priced higher than ANY variant in
-- category 'Accessories' (i.e. higher than the cheapest one)
SELECT pv.variant_id, pv.price
FROM product_variant pv
WHERE pv.price > ANY (
    SELECT pv2.price
    FROM product_variant pv2
    JOIN product p2          ON p2.product_id = pv2.product_id
    JOIN product_category pc ON pc.product_id = p2.product_id
    JOIN category c          ON c.category_id = pc.category_id
    WHERE c.name = 'Accessories'
);

-- 8.7 Subquery with ALL — variants priced higher than ALL variants in
-- category 'Accessories' (i.e. higher than the most expensive one)
SELECT pv.variant_id, pv.price
FROM product_variant pv
WHERE pv.price > ALL (
    SELECT pv2.price
    FROM product_variant pv2
    JOIN product p2          ON p2.product_id = pv2.product_id
    JOIN product_category pc ON pc.product_id = p2.product_id
    JOIN category c          ON c.category_id = pc.category_id
    WHERE c.name = 'Accessories'
);

-- 8.8 Subquery in FROM (derived table) — top spending customers
SELECT ranked.user_id, ranked.total_spent
FROM (
    SELECT user_id, SUM(total_amount) AS total_spent
    FROM orders
    GROUP BY user_id
) AS ranked
WHERE ranked.total_spent > 20000
ORDER BY ranked.total_spent DESC;

-- 8.9 Nested correlated subquery — order items priced above the average
-- price of items within the same order (identifying the "expensive" item
-- per order)
SELECT oi.order_item_id, oi.order_id, oi.unit_price
FROM order_item oi
WHERE oi.unit_price > (
    SELECT AVG(oi2.unit_price)
    FROM order_item oi2
    WHERE oi2.order_id = oi.order_id
);


-- =====================================================================
-- 9. NULL VALUES
-- NULL means "unknown / not applicable". Comparisons with NULL are
-- UNKNOWN (three-valued logic), so IS NULL / IS NOT NULL must be used.
-- =====================================================================

-- 9.1 IS NULL: payments that have not been completed yet (no paid_at)
SELECT payment_id, order_id, payment_method, payment_status
FROM payment
WHERE paid_at IS NULL;

-- 9.2 IS NOT NULL: shipments that have actually been delivered
SELECT shipment_id, order_id, carrier, delivered_at
FROM shipment
WHERE delivered_at IS NOT NULL;

-- 9.3 "= NULL" never matches anything (UNKNOWN is not TRUE)
SELECT COUNT(*) AS rows_with_eq_null   FROM address WHERE address_line2 = NULL;   -- 0
SELECT COUNT(*) AS rows_with_is_null   FROM address WHERE address_line2 IS NULL;  -- 10

-- 9.4 Three-valued logic truth table (1 = TRUE, 0 = FALSE, NULL = UNKNOWN)
SELECT NULL = NULL      AS null_eq_null,
       NULL <> 1        AS null_ne_1,
       NULL AND FALSE   AS null_and_false,
       NULL AND TRUE    AS null_and_true,
       NULL OR TRUE     AS null_or_true,
       NULL OR FALSE    AS null_or_false,
       NOT NULL         AS not_null;

-- 9.5 Aggregates ignore NULL: COUNT(*) counts rows, COUNT(col) counts non-NULL values
SELECT COUNT(*)                AS all_payments,
       COUNT(transaction_ref)  AS payments_with_reference,
       COUNT(paid_at)          AS payments_completed
FROM payment;

-- 9.6 AVG ignores NULL: average resolution time only over resolved returns
SELECT COUNT(*)              AS all_returns,
       COUNT(resolved_at)    AS resolved_returns,
       ROUND(AVG(TIMESTAMPDIFF(HOUR, requested_at, resolved_at)), 1) AS avg_hours_to_resolve
FROM return_request;

-- 9.7 COALESCE / IFNULL: replace NULL with a display value
SELECT address_id,
       address_line1,
       COALESCE(address_line2, '-')            AS address_line2,
       IFNULL(NULL, 'shown when value is NULL') AS ifnull_demo
FROM address
LIMIT 5;

-- 9.8 NULL trap with NOT IN: if the subquery returns a NULL, NOT IN
-- returns no rows at all. NOT EXISTS does not have this problem.
SELECT COUNT(*) AS not_in_with_null
FROM product
WHERE product_id NOT IN (SELECT 99 UNION SELECT NULL);          -- 0 rows

SELECT COUNT(*) AS not_exists_with_null
FROM product p
WHERE NOT EXISTS (SELECT 1 FROM (SELECT 99 AS id UNION SELECT NULL) x
                  WHERE x.id = p.product_id);                    -- 7 rows

-- 9.9 NULL sorts first in ascending order
SELECT order_id, shipped_at
FROM shipment
ORDER BY shipped_at ASC;


-- =====================================================================
-- 10. DATABASE MODIFICATION WITH SUBQUERIES
-- Each change is undone at the end of the section, so the seed data
-- (and all later consistency checks) are unaffected.
-- =====================================================================

-- 10.1 INSERT ... SELECT: move everything in Aarav's cart into his wishlist
--      (skipping items already there)
INSERT INTO wishlist_item (wishlist_id, variant_id)
SELECT w.wishlist_id, ci.variant_id
FROM cart c
JOIN cart_item ci ON ci.cart_id = c.cart_id
JOIN wishlist w   ON w.user_id = c.user_id
WHERE c.user_id = 1
  AND NOT EXISTS (
      SELECT 1 FROM wishlist_item wi
      WHERE wi.wishlist_id = w.wishlist_id AND wi.variant_id = ci.variant_id
  );

SELECT wi.wishlist_id, wi.variant_id, pv.sku
FROM wishlist_item wi
JOIN product_variant pv ON pv.variant_id = wi.variant_id
WHERE wi.wishlist_id = (SELECT wishlist_id FROM wishlist WHERE user_id = 1);

-- 10.2 UPDATE with a correlated subquery: raise the reorder level of every
--      variant that has sold at least once (reorder_level + units sold)
UPDATE inventory i
SET i.reorder_level = i.reorder_level + (
        SELECT COALESCE(SUM(oi.quantity), 0)
        FROM order_item oi
        WHERE oi.variant_id = i.variant_id)
WHERE i.variant_id IN (SELECT variant_id FROM order_item);

SELECT inventory_id, variant_id, quantity, reorder_level FROM inventory;

-- Undo 10.2 (same subquery, subtracted)
UPDATE inventory i
SET i.reorder_level = i.reorder_level - (
        SELECT COALESCE(SUM(oi.quantity), 0)
        FROM order_item oi
        WHERE oi.variant_id = i.variant_id)
WHERE i.variant_id IN (SELECT variant_id FROM order_item);

-- 10.3 DELETE with a subquery: remove from Aarav's wishlist anything that
--      is also in his cart (undoes 10.1)
DELETE FROM wishlist_item
WHERE wishlist_id = (SELECT wishlist_id FROM wishlist WHERE user_id = 1)
  AND variant_id IN (
      SELECT ci.variant_id
      FROM cart_item ci
      JOIN cart c ON c.cart_id = ci.cart_id
      WHERE c.user_id = 1
  );

SELECT COUNT(*) AS aarav_wishlist_items_after_cleanup     -- back to 2
FROM wishlist_item
WHERE wishlist_id = (SELECT wishlist_id FROM wishlist WHERE user_id = 1);
