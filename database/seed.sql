USE ecommerce_marketplace;

-- ============================================================
-- SEED DATA
-- Run order: schema.sql -> seed.sql -> week files.
-- Load this BEFORE week3_database_objects.sql: the Week 3 triggers
-- deduct stock on every order_item insert, and the stock levels below
-- already account for these historical orders.
--
-- Conventions used in this data set:
--   * orders.total_amount = SUM(quantity * unit_price) - coupon discounts
--   * payment.amount      = orders.total_amount
--   * inventory.quantity  = SUM(inventory_transaction.quantity)
--   * returns are only raised on DELIVERED orders, and refunds only
--     exist for APPROVED / RECEIVED / COMPLETED returns
-- ============================================================

-- ============================================================
-- 1. USERS
-- password_hash holds bcrypt hashes (cost 10). Every demo account
-- uses the password: Password@123
-- ============================================================

INSERT INTO users
    (name, email, password_hash, phone, role)
VALUES
    ('Aarav Mehta', 'aarav@example.com', '$2b$10$09ORWOnykRfy3.cW241Tn.9h9a/X.amcFEnGHv6mSQolnOEpglwMi', '9876500001', 'CUSTOMER'),
    ('Diya Sharma', 'diya@example.com', '$2b$10$P6c1kl3.dME7qhs5u33kDe4iG5frh1n4WcCw5lEtNpczhgTBNa8te', '9876500002', 'CUSTOMER'),
    ('Rohan Patel', 'rohan@example.com', '$2b$10$2dof7k1tVBGu3qwph0mux.Oh/Y0DGT5vcqtDDLgpBU0Z.KVx74icS', '9876500003', 'CUSTOMER'),
    ('Neha Iyer', 'neha@example.com', '$2b$10$aOvl1RfHrGv54e23WjiQzeG33GKzeaV0t1hcvt2VIiXvxTnjNBA42', '9876500004', 'CUSTOMER'),
    ('TechWorld Store', 'techworld@example.com', '$2b$10$IeiISqVYpZ96ROGLZ9OCWOVHjE8Ya/6RRcX0LwOQJ6MFH2yHMUNSa', '9876500010', 'SELLER'),
    ('FashionHub Store', 'fashionhub@example.com', '$2b$10$N8Fnoq/h4uRA7BGJ23mLYeAYEsck/VNtHRu4qdUIqrsdhwTvl.u9G', '9876500011', 'SELLER'),
    ('HomeEssentials Store', 'homeessentials@example.com', '$2b$10$LnfXWQGysbuwvuJbrfKONezKLx1BrffF35JZ51dz5ecV0egJZ.5rO', '9876500012', 'SELLER'),
    ('System Admin', 'admin@example.com', '$2b$10$QUQLMisG0kyjLVbjkET01e57r1YaKPbYjq6jWnB/jHX8TQzaKq5yO', '9876500099', 'ADMIN'),
    ('UrbanTech Store', 'urbantech@example.com', '$2b$10$UhroCmWIAyRaw8XvbQePm.0SENfiz6rHyjlptNkytfXLmbgGYuD1O', '9876500013', 'SELLER'),
    ('EverydayGoods Store', 'everydaygoods@example.com', '$2b$10$7NpKjubYG5zrMONkBV8UZ.yG.uCU.Nzvo/BYfsRJV1i2j3hfcCkvm', '9876500014', 'SELLER'),
    ('Kavya Reddy', 'kavya@example.com', '$2b$10$dbYQ/5Hl0JMSpO/7rz1cDewyOwXY4smpkhafZ0eFgNQN6avCOKfD6', '9876500005', 'CUSTOMER'),
    ('Arjun Nair', 'arjun@example.com', '$2b$10$37VkhMQpGJ4j4p.wjZEmbO8aseua/9oV/XqnGqgSzGMvyGWzyHeM.', '9876500006', 'CUSTOMER');


-- ============================================================
-- 2. SELLER PROFILES
-- ============================================================

INSERT INTO seller_profile
    (user_id, store_name, business_name)
VALUES
    (5, 'TechWorld', 'TechWorld Electronics Pvt. Ltd.'),
    (6, 'FashionHub', 'FashionHub Retail Pvt. Ltd.'),
    (7, 'HomeEssentials', 'HomeEssentials India Pvt. Ltd.'),
    (9, 'UrbanTech', 'UrbanTech Retail Pvt. Ltd.'),
    (10, 'EverydayGoods', 'EverydayGoods Retail Pvt. Ltd.');


-- ============================================================
-- 3. ADDRESSES
-- ============================================================

INSERT INTO address
    (user_id, address_line1, address_line2, city, state, postal_code, country, address_type)
VALUES
    (1, '12 MG Road', NULL, 'Bengaluru', 'Karnataka', '560001', 'India', 'HOME'),
    (1, '45 College Road', 'Block B', 'Bengaluru', 'Karnataka', '560029', 'India', 'WORK'),
    (2, '22 Park Street', NULL, 'Pune', 'Maharashtra', '411001', 'India', 'HOME'),
    (3, '18 Anna Nagar', NULL, 'Chennai', 'Tamil Nadu', '600040', 'India', 'HOME'),
    (4, '77 Koramangala', NULL, 'Bengaluru', 'Karnataka', '560034', 'India', 'HOME'),
    (5, '100 Electronic City', NULL, 'Bengaluru', 'Karnataka', '560100', 'India', 'WORK'),
    (6, '21 Commercial Street', NULL, 'Bengaluru', 'Karnataka', '560001', 'India', 'WORK'),
    (7, '9 Indiranagar', NULL, 'Bengaluru', 'Karnataka', '560038', 'India', 'WORK'),
    (11, '5 Jubilee Hills', 'Road No. 36', 'Hyderabad', 'Telangana', '500033', 'India', 'HOME'),
    (12, '14 Marine Drive', NULL, 'Kochi', 'Kerala', '682031', 'India', 'HOME'),
    (9, '60 Whitefield Main Road', NULL, 'Bengaluru', 'Karnataka', '560066', 'India', 'WORK'),
    (10, '33 HSR Layout', NULL, 'Bengaluru', 'Karnataka', '560102', 'India', 'WORK');


-- ============================================================
-- 4. BRANDS
-- ============================================================

INSERT INTO brand
    (name)
VALUES
    ('Apple'),
    ('Samsung'),
    ('Nike'),
    ('Adidas'),
    ('IKEA'),
    ('Logitech');


-- ============================================================
-- 5. CATEGORIES
-- ============================================================

INSERT INTO category
    (name)
VALUES
    ('Electronics'),
    ('Smartphones'),
    ('Laptops'),
    ('Fashion'),
    ('Footwear'),
    ('Home'),
    ('Accessories');


-- ============================================================
-- 6. PRODUCTS
-- ============================================================

INSERT INTO product
    (seller_id, brand_id, name, description, status)
VALUES
    (5, 1, 'iPhone 16', 'Latest Apple smartphone', 'ACTIVE'),
    (5, 2, 'Galaxy S25', 'Samsung flagship smartphone', 'ACTIVE'),
    (5, 6, 'MX Master 3S', 'Wireless productivity mouse', 'ACTIVE'),
    (5, 1, 'MacBook Air M4', 'Lightweight Apple laptop', 'ACTIVE'),
    (6, 3, 'Air Max 270', 'Nike lifestyle running shoe', 'ACTIVE'),
    (6, 4, 'Ultraboost Light', 'Adidas performance running shoe', 'ACTIVE'),
    (7, 5, 'KALLAX Shelf', 'Modular storage shelf', 'ACTIVE');


-- ============================================================
-- 7. PRODUCT CATEGORIES
-- ============================================================

INSERT INTO product_category
    (product_id, category_id)
VALUES
    (1, 1), -- iPhone -> Electronics
    (1, 2), -- iPhone -> Smartphones
    (2, 1), -- Galaxy -> Electronics
    (2, 2), -- Galaxy -> Smartphones
    (3, 1), -- Mouse -> Electronics
    (3, 7), -- Mouse -> Accessories
    (4, 1), -- MacBook -> Electronics
    (4, 3), -- MacBook -> Laptops
    (5, 4), -- Nike -> Fashion
    (5, 5), -- Nike -> Footwear
    (6, 4), -- Adidas -> Fashion
    (6, 5), -- Adidas -> Footwear
    (7, 6); -- Shelf -> Home


-- ============================================================
-- 8. PRODUCT VARIANTS
-- ============================================================

INSERT INTO product_variant
    (product_id, sku, price)
VALUES
    (1, 'IPH16-128-BLK', 69999.00),
    (1, 'IPH16-256-BLK', 79999.00),
    (2, 'S25-128-BLK', 74999.00),
    (2, 'S25-256-BLK', 84999.00),
    (3, 'MX3S-BLK', 8495.00),
    (4, 'MBA-M4-16-512', 114999.00),
    (5, 'AM270-BLK-9', 12999.00),
    (5, 'AM270-BLK-10', 12999.00),
    (6, 'UB-LIGHT-BLU-9', 15999.00),
    (7, 'KALLAX-WHT', 6999.00);


-- ============================================================
-- 9. ATTRIBUTES
-- ============================================================

INSERT INTO attribute
    (name)
VALUES
    ('Storage'),
    ('Color'),
    ('Size'),
    ('RAM'),
    ('Material');


-- ============================================================
-- 10. ATTRIBUTE VALUES
-- ============================================================

INSERT INTO attribute_value
    (attribute_id, value)
VALUES
    (1, '128GB'),
    (1, '256GB'),
    (1, '512GB'),
    (2, 'Black'),
    (2, 'Blue'),
    (2, 'White'),
    (3, '9'),
    (3, '10'),
    (4, '16GB'),
    (5, 'Engineered Wood');


-- ============================================================
-- 11. VARIANT ATTRIBUTES
-- ============================================================

INSERT INTO variant_attribute
    (variant_id, attribute_value_id)
VALUES
    (1, 1), -- iPhone 128GB
    (1, 4), -- Black

    (2, 2), -- iPhone 256GB
    (2, 4), -- Black

    (3, 1), -- S25 128GB
    (3, 4), -- Black

    (4, 2), -- S25 256GB
    (4, 4), -- Black

    (5, 4), -- Mouse Black

    (6, 3), -- MacBook 512GB
    (6, 9), -- MacBook 16GB RAM

    (7, 4), -- Nike Black
    (7, 7), -- Nike Size 9

    (8, 4), -- Nike Black
    (8, 8), -- Nike Size 10

    (9, 5), -- Adidas Blue
    (9, 7), -- Adidas Size 9

    (10, 6),  -- Shelf White
    (10, 10); -- Shelf Engineered Wood


-- ============================================================
-- 12. PRODUCT IMAGES
-- ============================================================

INSERT INTO product_image
    (product_id, image_url, display_order)
VALUES
    (1, 'https://example.com/images/iphone16-main.jpg', 1),
    (1, 'https://example.com/images/iphone16-side.jpg', 2),
    (2, 'https://example.com/images/galaxy-s25-main.jpg', 1),
    (3, 'https://example.com/images/mx-master-3s.jpg', 1),
    (4, 'https://example.com/images/macbook-air-m4.jpg', 1),
    (5, 'https://example.com/images/air-max-270.jpg', 1),
    (6, 'https://example.com/images/ultraboost.jpg', 1),
    (7, 'https://example.com/images/kallax.jpg', 1);


-- ============================================================
-- 13. CARTS (customers only)
-- ============================================================

INSERT INTO cart
    (user_id)
VALUES
    (1),
    (2),
    (3),
    (11),
    (12);


-- ============================================================
-- 14. CART ITEMS
-- ============================================================

INSERT INTO cart_item
    (cart_id, variant_id, quantity)
VALUES
    (1, 2, 1),
    (1, 5, 2),
    (2, 7, 1),
    (3, 3, 1),
    (4, 4, 1),
    (5, 6, 1);


-- ============================================================
-- 15. WISHLISTS (customers only)
-- ============================================================

INSERT INTO wishlist
    (user_id)
VALUES
    (1),
    (2),
    (4),
    (11),
    (12);


-- ============================================================
-- 16. WISHLIST ITEMS
-- ============================================================

INSERT INTO wishlist_item
    (wishlist_id, variant_id)
VALUES
    (1, 6),
    (1, 9),
    (2, 1),
    (3, 10),
    (4, 2),
    (5, 3);


-- ============================================================
-- 17. INVENTORY  (current stock, after all orders below)
-- ============================================================

INSERT INTO inventory
    (variant_id, quantity, reorder_level)
VALUES
    (1, 25, 5),
    (2, 12, 5),
    (3, 18, 5),
    (4, 8, 5),
    (5, 30, 10),
    (6, 6, 3),
    (7, 15, 5),
    (8, 3, 5),
    (9, 20, 5),
    (10, 2, 5);


-- ============================================================
-- 18. INVENTORY TRANSACTIONS  (stock ledger)
-- RESTOCK +, PURCHASE -, RETURN +, ADJUSTMENT +/-.
-- For every variant, SUM(quantity) here = inventory.quantity.
-- ============================================================

INSERT INTO inventory_transaction
    (inventory_id, transaction_type, quantity, reference_type, reference_id, created_at)
VALUES
    -- Opening stock
    (1, 'RESTOCK', 25, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (2, 'RESTOCK', 13, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (3, 'RESTOCK', 19, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (4, 'RESTOCK', 8, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (5, 'RESTOCK', 32, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (6, 'RESTOCK', 6, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (7, 'RESTOCK', 16, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (8, 'RESTOCK', 3, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (9, 'RESTOCK', 20, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),
    (10, 'RESTOCK', 5, 'INITIAL_STOCK', NULL, '2026-08-01 09:00:00'),

    -- Sales (one row per order item)
    (2, 'PURCHASE', -1, 'ORDER', 1, '2026-08-10 10:30:00'),
    (7, 'PURCHASE', -1, 'ORDER', 2, '2026-08-12 14:20:00'),
    (5, 'PURCHASE', -1, 'ORDER', 3, '2026-08-15 09:15:00'),
    (10, 'PURCHASE', -1, 'ORDER', 4, '2026-08-17 18:00:00'),
    (1, 'PURCHASE', -1, 'ORDER', 5, '2026-08-20 11:00:00'),
    (9, 'PURCHASE', -1, 'ORDER', 6, '2026-08-22 13:10:00'),
    (5, 'PURCHASE', -1, 'ORDER', 6, '2026-08-22 13:10:00'),
    (3, 'PURCHASE', -1, 'ORDER', 7, '2026-08-25 16:45:00'),
    (8, 'PURCHASE', -1, 'ORDER', 8, '2026-08-27 12:00:00'),
    (10, 'PURCHASE', -2, 'ORDER', 9, '2026-08-29 19:30:00'),
    (6, 'PURCHASE', -1, 'ORDER', 10, '2026-09-02 10:05:00'),

    -- Order 10 was cancelled: stock put back
    (6, 'ADJUSTMENT', 1, 'ORDER_CANCELLED', 10, '2026-09-02 10:10:00'),

    -- Completed returns restocked (reference = return_id)
    (1, 'RETURN', 1, 'RETURN_REQUEST', 6, '2026-08-27 12:00:00'),
    (9, 'RETURN', 1, 'RETURN_REQUEST', 1, '2026-08-29 12:00:00'),
    (8, 'RETURN', 1, 'RETURN_REQUEST', 2, '2026-09-02 12:00:00');


-- ============================================================
-- 19. ORDERS
-- total_amount = item subtotal - coupon discount (see order_coupon)
-- ============================================================

INSERT INTO orders
    (user_id, shipping_address_id, order_date, status, total_amount)
VALUES
    (1, 1, '2026-08-10 10:30:00', 'DELIVERED', 71999.10),   -- 79999.00 - 7999.90
    (2, 3, '2026-08-12 14:20:00', 'SHIPPED', 12499.00),     -- 12999.00 - 500.00
    (3, 4, '2026-08-15 09:15:00', 'CONFIRMED', 7220.75),    --  8495.00 - 1274.25
    (4, 5, '2026-08-17 18:00:00', 'PROCESSING', 6249.00),   --  6999.00 - 750.00
    (1, 1, '2026-08-20 11:00:00', 'RETURNED', 66499.05),    -- 69999.00 - 3499.95
    (11, 9, '2026-08-22 13:10:00', 'DELIVERED', 24494.00),
    (12, 10, '2026-08-25 16:45:00', 'DELIVERED', 74999.00),
    (2, 3, '2026-08-27 12:00:00', 'DELIVERED', 12999.00),
    (3, 4, '2026-08-29 19:30:00', 'DELIVERED', 13998.00),
    (4, 5, '2026-09-02 10:05:00', 'CANCELLED', 114999.00);


-- ============================================================
-- 20. ORDER ITEMS
-- unit_price is the price at purchase time.
-- ============================================================

INSERT INTO order_item
    (order_id, variant_id, quantity, unit_price)
VALUES
    (1, 2, 1, 79999.00),
    (2, 7, 1, 12999.00),
    (3, 5, 1, 8495.00),
    (4, 10, 1, 6999.00),
    (5, 1, 1, 69999.00),
    (6, 9, 1, 15999.00),
    (6, 5, 1, 8495.00),
    (7, 3, 1, 74999.00),
    (8, 8, 1, 12999.00),
    (9, 10, 2, 6999.00),
    (10, 6, 1, 114999.00);


-- ============================================================
-- 21. PAYMENTS  (amount = orders.total_amount)
-- ============================================================

INSERT INTO payment
    (order_id, amount, payment_method, payment_status, transaction_ref, paid_at)
VALUES
    (1, 71999.10, 'UPI', 'SUCCESS', 'TXN10001', '2026-08-10 10:32:00'),
    (2, 12499.00, 'CARD', 'SUCCESS', 'TXN10002', '2026-08-12 14:22:00'),
    (3, 7220.75, 'UPI', 'SUCCESS', 'TXN10003', '2026-08-15 09:17:00'),
    (4, 6249.00, 'COD', 'PENDING', NULL, NULL),
    (5, 66499.05, 'CARD', 'REFUNDED', 'TXN10005', '2026-08-20 11:02:00'),
    (6, 24494.00, 'CARD', 'SUCCESS', 'TXN10006', '2026-08-22 13:12:00'),
    (7, 74999.00, 'NET_BANKING', 'SUCCESS', 'TXN10007', '2026-08-25 16:47:00'),
    (8, 12999.00, 'UPI', 'SUCCESS', 'TXN10008', '2026-08-27 12:02:00'),
    (9, 13998.00, 'COD', 'SUCCESS', 'COD10009', '2026-08-31 18:00:00'),
    (10, 114999.00, 'CARD', 'FAILED', 'TXN10010', NULL);


-- ============================================================
-- 22. SHIPMENTS  (none for the cancelled order 10)
-- ============================================================

INSERT INTO shipment
    (order_id, carrier, tracking_number, shipment_status, shipped_at, delivered_at)
VALUES
    (1, 'BlueDart', 'BD100001', 'DELIVERED', '2026-08-11 09:00:00', '2026-08-13 16:00:00'),
    (2, 'Delhivery', 'DL100002', 'IN_TRANSIT', '2026-08-14 11:00:00', NULL),
    (3, 'DTDC', 'DT100003', 'PENDING', NULL, NULL),
    (4, 'BlueDart', 'BD100004', 'PENDING', NULL, NULL),
    (5, 'Delhivery', 'DL100005', 'DELIVERED', '2026-08-21 09:00:00', '2026-08-22 16:00:00'),
    (6, 'BlueDart', 'BD100006', 'DELIVERED', '2026-08-23 10:00:00', '2026-08-25 15:00:00'),
    (7, 'Delhivery', 'DL100007', 'DELIVERED', '2026-08-26 14:00:00', '2026-08-27 17:00:00'),
    (8, 'DTDC', 'DT100008', 'DELIVERED', '2026-08-28 10:00:00', '2026-08-29 13:00:00'),
    (9, 'BlueDart', 'BD100009', 'DELIVERED', '2026-08-30 15:00:00', '2026-08-31 18:00:00');


-- ============================================================
-- 23. ORDER STATUS HISTORY
-- ============================================================

INSERT INTO order_status_history
    (order_id, old_status, new_status, changed_at)
VALUES
    (1, 'PENDING', 'CONFIRMED', '2026-08-10 10:35:00'),
    (1, 'CONFIRMED', 'PROCESSING', '2026-08-10 15:00:00'),
    (1, 'PROCESSING', 'SHIPPED', '2026-08-11 09:00:00'),
    (1, 'SHIPPED', 'DELIVERED', '2026-08-13 16:00:00'),

    (2, 'PENDING', 'CONFIRMED', '2026-08-12 14:25:00'),
    (2, 'CONFIRMED', 'PROCESSING', '2026-08-13 10:00:00'),
    (2, 'PROCESSING', 'SHIPPED', '2026-08-14 11:00:00'),

    (3, 'PENDING', 'CONFIRMED', '2026-08-15 09:20:00'),

    (4, 'PENDING', 'CONFIRMED', '2026-08-17 18:05:00'),
    (4, 'CONFIRMED', 'PROCESSING', '2026-08-18 10:00:00'),

    (5, 'PENDING', 'CONFIRMED', '2026-08-20 11:05:00'),
    (5, 'CONFIRMED', 'PROCESSING', '2026-08-20 16:00:00'),
    (5, 'PROCESSING', 'SHIPPED', '2026-08-21 09:00:00'),
    (5, 'SHIPPED', 'DELIVERED', '2026-08-22 16:00:00'),
    (5, 'DELIVERED', 'RETURNED', '2026-08-27 12:00:00'),

    (6, 'PENDING', 'CONFIRMED', '2026-08-22 13:15:00'),
    (6, 'CONFIRMED', 'PROCESSING', '2026-08-22 18:00:00'),
    (6, 'PROCESSING', 'SHIPPED', '2026-08-23 10:00:00'),
    (6, 'SHIPPED', 'DELIVERED', '2026-08-25 15:00:00'),

    (7, 'PENDING', 'CONFIRMED', '2026-08-25 16:50:00'),
    (7, 'CONFIRMED', 'PROCESSING', '2026-08-26 09:00:00'),
    (7, 'PROCESSING', 'SHIPPED', '2026-08-26 14:00:00'),
    (7, 'SHIPPED', 'DELIVERED', '2026-08-27 17:00:00'),

    (8, 'PENDING', 'CONFIRMED', '2026-08-27 12:05:00'),
    (8, 'CONFIRMED', 'PROCESSING', '2026-08-27 17:00:00'),
    (8, 'PROCESSING', 'SHIPPED', '2026-08-28 10:00:00'),
    (8, 'SHIPPED', 'DELIVERED', '2026-08-29 13:00:00'),

    (9, 'PENDING', 'CONFIRMED', '2026-08-29 19:35:00'),
    (9, 'CONFIRMED', 'PROCESSING', '2026-08-30 09:00:00'),
    (9, 'PROCESSING', 'SHIPPED', '2026-08-30 15:00:00'),
    (9, 'SHIPPED', 'DELIVERED', '2026-08-31 18:00:00'),

    (10, 'PENDING', 'CANCELLED', '2026-09-02 10:10:00');


-- ============================================================
-- 24. REVIEWS  (each reviewer bought and received the product)
-- ============================================================

INSERT INTO review
    (user_id, product_id, rating, comment, created_at)
VALUES
    (1, 1, 5, 'Excellent phone and very good performance.', '2026-08-15 20:00:00'),
    (2, 5, 4, 'Comfortable shoes and good build quality.', '2026-08-31 18:30:00'),
    (11, 3, 5, 'Excellent mouse for productivity.', '2026-08-27 21:00:00'),
    (3, 7, 4, 'Good storage solution for the price.', '2026-09-02 19:00:00'),
    (12, 2, 3, 'Bright display, but my unit had a few dead pixels.', '2026-08-28 10:30:00'),
    (11, 6, 3, 'Light and comfortable, but the sizing runs small.', '2026-08-26 22:15:00');


-- ============================================================
-- 25. COUPONS
-- ============================================================

INSERT INTO coupon
    (code, discount_type, discount_value, minimum_amount,
     start_date, expiry_date, usage_limit)
VALUES
    ('WELCOME10', 'PERCENTAGE', 10.00, 5000.00,
     '2026-08-01 00:00:00', '2026-12-31 23:59:59', 100),
    ('FLAT500', 'FIXED', 500.00, 10000.00,
     '2026-08-01 00:00:00', '2026-10-31 23:59:59', 50),
    ('TECH15', 'PERCENTAGE', 15.00, 5000.00,
     '2026-08-01 00:00:00', '2026-12-31 23:59:59', 100),
    ('FESTIVE750', 'FIXED', 750.00, 6000.00,
     '2026-08-01 00:00:00', '2026-12-31 23:59:59', 75),
    ('NEWUSER5', 'PERCENTAGE', 5.00, 1000.00,
     '2026-08-01 00:00:00', '2026-12-31 23:59:59', 200);


-- ============================================================
-- 26. ORDER COUPONS
-- PERCENTAGE: subtotal * value / 100 ; FIXED: value
-- ============================================================

INSERT INTO order_coupon
    (order_id, coupon_id, discount_amount)
VALUES
    (1, 1, 7999.90),   -- 10% of 79999.00
    (2, 2, 500.00),    -- flat 500
    (3, 3, 1274.25),   -- 15% of 8495.00
    (4, 4, 750.00),    -- flat 750
    (5, 5, 3499.95);   -- 5% of 69999.00


-- ============================================================
-- 27. RETURN REQUESTS  (only on delivered orders)
-- ============================================================

INSERT INTO return_request
    (order_item_id, reason, status, requested_at, resolved_at)
VALUES
    (6, 'Size was not suitable', 'COMPLETED',
     '2026-08-26 10:00:00', '2026-08-29 12:00:00'),
    (9, 'Received the wrong size', 'COMPLETED',
     '2026-08-30 10:00:00', '2026-09-02 12:00:00'),
    (8, 'Display has dead pixels', 'APPROVED',
     '2026-08-28 11:00:00', '2026-08-30 12:00:00'),
    (10, 'One of the two units arrived damaged', 'RECEIVED',
     '2026-09-01 09:00:00', NULL),
    (1, 'Changed mind after the 10-day return window', 'REJECTED',
     '2026-08-25 10:00:00', '2026-08-26 12:00:00'),
    (5, 'Battery drains quickly', 'COMPLETED',
     '2026-08-24 10:00:00', '2026-08-27 12:00:00');


-- ============================================================
-- 28. REFUNDS  (amount <= what was actually paid for the item;
--               no refund for the REJECTED return)
-- ============================================================

INSERT INTO refund
    (return_id, payment_id, amount, refund_status, refunded_at)
VALUES
    (1, 6, 15999.00, 'PROCESSED', '2026-08-30 15:00:00'),
    (2, 8, 12999.00, 'PROCESSED', '2026-09-03 15:00:00'),
    (3, 7, 74999.00, 'PENDING', NULL),
    (4, 9, 6999.00, 'PENDING', NULL),     -- 1 of the 2 units
    (6, 5, 66499.05, 'PROCESSED', '2026-08-28 15:00:00');
