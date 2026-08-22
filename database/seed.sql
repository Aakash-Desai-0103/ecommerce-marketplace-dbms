USE ecommerce_marketplace;

-- ============================================================
-- SEED DATA
-- ============================================================

-- ============================================================
-- 1. USERS
-- ============================================================

INSERT INTO users
    (name, email, password_hash, phone, role)
VALUES
    ('Aarav Mehta', 'aarav@example.com', 'HASH_PLACEHOLDER_1', '9876500001', 'CUSTOMER'),
    ('Diya Sharma', 'diya@example.com', 'HASH_PLACEHOLDER_2', '9876500002', 'CUSTOMER'),
    ('Rohan Patel', 'rohan@example.com', 'HASH_PLACEHOLDER_3', '9876500003', 'CUSTOMER'),
    ('Neha Iyer', 'neha@example.com', 'HASH_PLACEHOLDER_4', '9876500004', 'CUSTOMER'),
    ('TechWorld Store', 'techworld@example.com', 'HASH_PLACEHOLDER_5', '9876500010', 'SELLER'),
    ('FashionHub Store', 'fashionhub@example.com', 'HASH_PLACEHOLDER_6', '9876500011', 'SELLER'),
    ('HomeEssentials Store', 'homeessentials@example.com', 'HASH_PLACEHOLDER_7', '9876500012', 'SELLER'),
    ('System Admin', 'admin@example.com', 'HASH_PLACEHOLDER_8', '9876500099', 'ADMIN');


-- ============================================================
-- 2. SELLER PROFILES
-- ============================================================

INSERT INTO seller_profile
    (user_id, store_name, business_name)
VALUES
    (5, 'TechWorld', 'TechWorld Electronics Pvt. Ltd.'),
    (6, 'FashionHub', 'FashionHub Retail Pvt. Ltd.'),
    (7, 'HomeEssentials', 'HomeEssentials India Pvt. Ltd.');


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
    (7, '9 Indiranagar', NULL, 'Bengaluru', 'Karnataka', '560038', 'India', 'WORK');


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
    ('RAM');


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
    (4, '16GB');


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

    (10, 6); -- Shelf White


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
-- 13. CARTS
-- ============================================================

INSERT INTO cart
    (user_id)
VALUES
    (1),
    (2),
    (3);


-- ============================================================
-- 14. CART ITEMS
-- ============================================================

INSERT INTO cart_item
    (cart_id, variant_id, quantity)
VALUES
    (1, 2, 1),
    (1, 5, 2),
    (2, 7, 1),
    (3, 3, 1);


-- ============================================================
-- 15. WISHLISTS
-- ============================================================

INSERT INTO wishlist
    (user_id)
VALUES
    (1),
    (2),
    (4);


-- ============================================================
-- 16. WISHLIST ITEMS
-- ============================================================

INSERT INTO wishlist_item
    (wishlist_id, variant_id)
VALUES
    (1, 6),
    (1, 9),
    (2, 1),
    (3, 10);


-- ============================================================
-- 17. INVENTORY
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
-- 18. INVENTORY TRANSACTIONS
-- ============================================================

INSERT INTO inventory_transaction
    (inventory_id, transaction_type, quantity, reference_type, reference_id)
VALUES
    (1, 'RESTOCK', 25, 'INITIAL_STOCK', NULL),
    (2, 'RESTOCK', 12, 'INITIAL_STOCK', NULL),
    (3, 'RESTOCK', 18, 'INITIAL_STOCK', NULL),
    (4, 'RESTOCK', 8, 'INITIAL_STOCK', NULL),
    (5, 'RESTOCK', 30, 'INITIAL_STOCK', NULL),
    (6, 'RESTOCK', 6, 'INITIAL_STOCK', NULL),
    (7, 'RESTOCK', 15, 'INITIAL_STOCK', NULL),
    (8, 'RESTOCK', 3, 'INITIAL_STOCK', NULL),
    (9, 'RESTOCK', 20, 'INITIAL_STOCK', NULL),
    (10, 'RESTOCK', 2, 'INITIAL_STOCK', NULL);


-- ============================================================
-- 19. ORDERS
-- ============================================================

INSERT INTO orders
    (user_id, shipping_address_id, order_date, status, total_amount)
VALUES
    (1, 1, '2026-08-10 10:30:00', 'DELIVERED', 79999.00),
    (2, 3, '2026-08-12 14:20:00', 'SHIPPED', 12999.00),
    (3, 4, '2026-08-15 09:15:00', 'CONFIRMED', 8495.00),
    (4, 5, '2026-08-17 18:00:00', 'PROCESSING', 6999.00);


-- ============================================================
-- 20. ORDER ITEMS
-- ============================================================

INSERT INTO order_item
    (order_id, variant_id, quantity, unit_price)
VALUES
    (1, 2, 1, 79999.00),
    (2, 7, 1, 12999.00),
    (3, 5, 1, 8495.00),
    (4, 10, 1, 6999.00);


-- ============================================================
-- 21. PAYMENTS
-- ============================================================

INSERT INTO payment
    (order_id, amount, payment_method, payment_status, transaction_ref, paid_at)
VALUES
    (1, 79999.00, 'UPI', 'SUCCESS', 'TXN10001', '2026-08-10 10:32:00'),
    (2, 12999.00, 'CARD', 'SUCCESS', 'TXN10002', '2026-08-12 14:22:00'),
    (3, 8495.00, 'UPI', 'SUCCESS', 'TXN10003', '2026-08-15 09:17:00'),
    (4, 6999.00, 'COD', 'PENDING', NULL, NULL);


-- ============================================================
-- 22. SHIPMENTS
-- ============================================================

INSERT INTO shipment
    (order_id, carrier, tracking_number, shipment_status, shipped_at, delivered_at)
VALUES
    (1, 'BlueDart', 'BD100001', 'DELIVERED',
     '2026-08-11 09:00:00', '2026-08-13 16:00:00'),

    (2, 'Delhivery', 'DL100002', 'SHIPPED',
     '2026-08-14 11:00:00', NULL),

    (3, 'DTDC', 'DT100003', 'PENDING',
     NULL, NULL);


-- ============================================================
-- 23. ORDER STATUS HISTORY
-- ============================================================

INSERT INTO order_status_history
    (order_id, old_status, new_status)
VALUES
    (1, 'PENDING', 'CONFIRMED'),
    (1, 'CONFIRMED', 'PROCESSING'),
    (1, 'PROCESSING', 'SHIPPED'),
    (1, 'SHIPPED', 'DELIVERED'),

    (2, 'PENDING', 'CONFIRMED'),
    (2, 'CONFIRMED', 'PROCESSING'),
    (2, 'PROCESSING', 'SHIPPED'),

    (3, 'PENDING', 'CONFIRMED'),

    (4, 'PENDING', 'CONFIRMED'),
    (4, 'CONFIRMED', 'PROCESSING');


-- ============================================================
-- 24. REVIEWS
-- ============================================================

INSERT INTO review
    (user_id, product_id, rating, comment)
VALUES
    (1, 1, 5, 'Excellent phone and very good performance.'),
    (2, 5, 4, 'Comfortable shoes and good build quality.'),
    (3, 3, 5, 'Excellent mouse for productivity.'),
    (4, 7, 4, 'Good storage solution for the price.');


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
     '2026-08-01 00:00:00', '2026-10-31 23:59:59', 50);


-- ============================================================
-- 26. ORDER COUPONS
-- ============================================================

INSERT INTO order_coupon
    (order_id, coupon_id, discount_amount)
VALUES
    (1, 1, 7999.90);


-- ============================================================
-- 27. RETURN REQUESTS
-- ============================================================

INSERT INTO return_request
    (order_item_id, reason, status, requested_at, resolved_at)
VALUES
    (2, 'Size was not suitable', 'APPROVED',
     '2026-08-16 10:00:00', '2026-08-17 12:00:00');


-- ============================================================
-- 28. REFUND
-- ============================================================

INSERT INTO refund
    (return_id, payment_id, amount, refund_status, refunded_at)
VALUES
    (1, 2, 12999.00, 'PROCESSED', '2026-08-18 15:00:00');
