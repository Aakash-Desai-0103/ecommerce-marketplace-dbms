USE ecommerce_marketplace;

-- ============================================================
-- WEEK 5
-- WINDOW FUNCTIONS
-- E-Commerce Marketplace
-- ============================================================


-- ============================================================
-- 1. RANK()
-- Rank products based on their average customer rating
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    ROUND(AVG(r.rating), 2) AS average_rating,
    RANK() OVER (
        ORDER BY AVG(r.rating) DESC
    ) AS rating_rank
FROM product p
JOIN review r
    ON p.product_id = r.product_id
GROUP BY
    p.product_id,
    p.name
ORDER BY rating_rank;


-- ============================================================
-- 2. DENSE_RANK()
-- Rank sellers based on total sales revenue
-- ============================================================

SELECT
    p.seller_id,
    sp.store_name,
    SUM(oi.quantity * oi.unit_price) AS total_revenue,
    DENSE_RANK() OVER (
        ORDER BY SUM(oi.quantity * oi.unit_price) DESC
    ) AS seller_rank
FROM product p
JOIN seller_profile sp
    ON p.seller_id = sp.user_id
JOIN product_variant pv
    ON p.product_id = pv.product_id
JOIN order_item oi
    ON pv.variant_id = oi.variant_id
GROUP BY
    p.seller_id,
    sp.store_name
ORDER BY seller_rank;


-- ============================================================
-- 3. ROW_NUMBER()
-- Assign a unique number to products according to
-- their creation order
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.created_at,
    ROW_NUMBER() OVER (
        ORDER BY p.created_at
    ) AS product_number
FROM product p
ORDER BY product_number;


-- ============================================================
-- 4. PARTITION BY
-- Rank products within each category based on
-- average customer rating
-- ============================================================

SELECT
    c.category_id,
    c.name AS category_name,
    p.product_id,
    p.name AS product_name,
    ROUND(AVG(r.rating), 2) AS average_rating,
    RANK() OVER (
        PARTITION BY c.category_id
        ORDER BY AVG(r.rating) DESC
    ) AS category_rank
FROM category c
JOIN product_category pc
    ON c.category_id = pc.category_id
JOIN product p
    ON pc.product_id = p.product_id
JOIN review r
    ON p.product_id = r.product_id
GROUP BY
    c.category_id,
    c.name,
    p.product_id,
    p.name
ORDER BY
    c.name,
    category_rank;


-- ============================================================
-- 5. ROW_NUMBER() + PARTITION BY
-- Number each product within its category
-- ============================================================

SELECT
    c.name AS category_name,
    p.product_id,
    p.name AS product_name,
    ROW_NUMBER() OVER (
        PARTITION BY c.category_id
        ORDER BY p.name
    ) AS product_number_in_category
FROM category c
JOIN product_category pc
    ON c.category_id = pc.category_id
JOIN product p
    ON pc.product_id = p.product_id
ORDER BY
    c.name,
    product_number_in_category;


-- ============================================================
-- 6. LAG()
-- Compare each customer's order amount with
-- their previous order
-- ============================================================

SELECT
    o.user_id,
    u.name AS customer_name,
    o.order_id,
    o.order_date,
    o.total_amount,
    LAG(o.total_amount) OVER (
        PARTITION BY o.user_id
        ORDER BY o.order_date
    ) AS previous_order_amount
FROM orders o
JOIN users u
    ON o.user_id = u.user_id
ORDER BY
    o.user_id,
    o.order_date;


-- ============================================================
-- 7. LEAD()
-- Display the next order amount for each customer
-- ============================================================

SELECT
    o.user_id,
    u.name AS customer_name,
    o.order_id,
    o.order_date,
    o.total_amount,
    LEAD(o.total_amount) OVER (
        PARTITION BY o.user_id
        ORDER BY o.order_date
    ) AS next_order_amount
FROM orders o
JOIN users u
    ON o.user_id = u.user_id
ORDER BY
    o.user_id,
    o.order_date;


-- ============================================================
-- 8. RUNNING TOTAL
-- Calculate cumulative spending by each customer
-- ============================================================

SELECT
    o.user_id,
    u.name AS customer_name,
    o.order_id,
    o.order_date,
    o.total_amount,
    SUM(o.total_amount) OVER (
        PARTITION BY o.user_id
        ORDER BY o.order_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_spending
FROM orders o
JOIN users u
    ON o.user_id = u.user_id
ORDER BY
    o.user_id,
    o.order_date;


-- ============================================================
-- 9. WINDOW AVG()
-- Compare each product variant's price with
-- the average variant price of its product
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    pv.variant_id,
    pv.sku,
    pv.price,
    ROUND(
        AVG(pv.price) OVER (
            PARTITION BY pv.product_id
        ),
        2
    ) AS average_product_variant_price
FROM product p
JOIN product_variant pv
    ON p.product_id = pv.product_id
ORDER BY
    p.product_id,
    pv.price;


-- ============================================================
-- 10. PRICE DIFFERENCE FROM PRODUCT AVERAGE
-- Show how much each variant differs from the
-- average price of its product
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    pv.variant_id,
    pv.sku,
    pv.price,
    ROUND(
        AVG(pv.price) OVER (
            PARTITION BY pv.product_id
        ),
        2
    ) AS average_price,
    ROUND(
        pv.price -
        AVG(pv.price) OVER (
            PARTITION BY pv.product_id
        ),
        2
    ) AS difference_from_average
FROM product p
JOIN product_variant pv
    ON p.product_id = pv.product_id
ORDER BY
    p.product_id,
    pv.price;


-- ============================================================
-- 11. RUNNING REVENUE
-- Calculate cumulative revenue generated by
-- each seller's products
-- ============================================================

SELECT
    p.seller_id,
    sp.store_name,
    o.order_id,
    o.order_date,
    oi.quantity * oi.unit_price AS order_item_revenue,
    SUM(oi.quantity * oi.unit_price) OVER (
        PARTITION BY p.seller_id
        ORDER BY o.order_date, o.order_id
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_seller_revenue
FROM product p
JOIN seller_profile sp
    ON p.seller_id = sp.user_id
JOIN product_variant pv
    ON p.product_id = pv.product_id
JOIN order_item oi
    ON pv.variant_id = oi.variant_id
JOIN orders o
    ON oi.order_id = o.order_id
ORDER BY
    p.seller_id,
    o.order_date,
    o.order_id;


-- ============================================================
-- 12. NTILE()
-- Divide products into performance groups according
-- to their average rating
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    ROUND(AVG(r.rating), 2) AS average_rating,
    NTILE(3) OVER (
        ORDER BY AVG(r.rating) DESC
    ) AS rating_group
FROM product p
JOIN review r
    ON p.product_id = r.product_id
GROUP BY
    p.product_id,
    p.name
ORDER BY rating_group, average_rating DESC;

-- ============================================================
-- ============================================================
-- PART 2 — TEXT-BASED SEARCH
-- MATCH ... AGAINST
-- ============================================================
-- ============================================================


-- ============================================================
-- 13. CREATE FULLTEXT INDEX
-- Enable text-based searching on product name and description
-- ============================================================

ALTER TABLE product
ADD FULLTEXT INDEX ft_product_name_description
(name, description);


-- ============================================================
-- 14. NATURAL LANGUAGE SEARCH
-- Search for products related to "laptop"
-- Results are ordered by relevance
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('laptop' IN NATURAL LANGUAGE MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('laptop' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 15. NATURAL LANGUAGE SEARCH WITH MULTIPLE KEYWORDS
-- Search for products related to smartphones
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('smartphone' IN NATURAL LANGUAGE MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('smartphone' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 16. SEARCH FOR MULTIPLE PRODUCT CHARACTERISTICS
-- Search for products related to Apple and performance
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('Apple performance' IN NATURAL LANGUAGE MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('Apple performance' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 17. BOOLEAN MODE SEARCH
-- Require the word "smartphone"
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('+smartphone' IN BOOLEAN MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('+smartphone' IN BOOLEAN MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 18. BOOLEAN MODE SEARCH WITH EXCLUSION
-- Find smartphone products but exclude Samsung
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('+smartphone -Samsung' IN BOOLEAN MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('+smartphone -Samsung' IN BOOLEAN MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 19. SEARCH PRODUCT DESCRIPTIONS
-- Search for products related to "running shoe"
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('running shoe' IN NATURAL LANGUAGE MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('running shoe' IN NATURAL LANGUAGE MODE)
ORDER BY relevance DESC;


-- ============================================================
-- 20. SEARCH WITH RELEVANCE THRESHOLD
-- Display products matching "Apple" and show their
-- calculated relevance score
-- ============================================================

SELECT
    p.product_id,
    p.name AS product_name,
    p.description,
    MATCH(p.name, p.description)
        AGAINST('Apple' IN NATURAL LANGUAGE MODE) AS relevance
FROM product p
WHERE MATCH(p.name, p.description)
        AGAINST('Apple' IN NATURAL LANGUAGE MODE) > 0
ORDER BY relevance DESC;