-- ============================================================
-- E-COMMERCE MARKETPLACE DBMS
-- Week 1 - Database Foundation
-- MySQL 8.0+
-- ============================================================

CREATE DATABASE IF NOT EXISTS ecommerce_marketplace;

USE ecommerce_marketplace;


-- ============================================================
-- 1. USERS / AUTHENTICATION
-- ============================================================

CREATE TABLE users (
    user_id BIGINT UNSIGNED AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    role ENUM('CUSTOMER', 'SELLER', 'ADMIN') NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_users
        PRIMARY KEY (user_id),

    CONSTRAINT uq_users_email
        UNIQUE (email)
);


-- ============================================================
-- 2. SELLER PROFILE
-- ============================================================

CREATE TABLE seller_profile (
    user_id BIGINT UNSIGNED,
    store_name VARCHAR(150) NOT NULL,
    business_name VARCHAR(150),

    CONSTRAINT pk_seller_profile
        PRIMARY KEY (user_id),

    CONSTRAINT fk_seller_profile_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 3. ADDRESS
-- ============================================================

CREATE TABLE address (
    address_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    address_line1 VARCHAR(200) NOT NULL,
    address_line2 VARCHAR(200),
    city VARCHAR(100) NOT NULL,
    state VARCHAR(100) NOT NULL,
    postal_code VARCHAR(20) NOT NULL,
    country VARCHAR(100) NOT NULL DEFAULT 'India',
    address_type ENUM('HOME', 'WORK', 'OTHER') NOT NULL DEFAULT 'HOME',

    CONSTRAINT pk_address
        PRIMARY KEY (address_id),

    CONSTRAINT fk_address_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 4. BRAND
-- ============================================================

CREATE TABLE brand (
    brand_id BIGINT UNSIGNED AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,

    CONSTRAINT pk_brand
        PRIMARY KEY (brand_id),

    CONSTRAINT uq_brand_name
        UNIQUE (name)
);


-- ============================================================
-- 5. CATEGORY
-- ============================================================

CREATE TABLE category (
    category_id BIGINT UNSIGNED AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,

    CONSTRAINT pk_category
        PRIMARY KEY (category_id),

    CONSTRAINT uq_category_name
        UNIQUE (name)
);


-- ============================================================
-- 6. PRODUCT
-- ============================================================

CREATE TABLE product (
    product_id BIGINT UNSIGNED AUTO_INCREMENT,
    seller_id BIGINT UNSIGNED NOT NULL,
    brand_id BIGINT UNSIGNED NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    status ENUM('ACTIVE', 'INACTIVE', 'DISCONTINUED') NOT NULL
        DEFAULT 'ACTIVE',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_product
        PRIMARY KEY (product_id),

    CONSTRAINT fk_product_seller
        FOREIGN KEY (seller_id)
        REFERENCES seller_profile(user_id),

    CONSTRAINT fk_product_brand
        FOREIGN KEY (brand_id)
        REFERENCES brand(brand_id)
);


-- ============================================================
-- 7. PRODUCT <-> CATEGORY
-- ============================================================

CREATE TABLE product_category (
    product_id BIGINT UNSIGNED,
    category_id BIGINT UNSIGNED,

    CONSTRAINT pk_product_category
        PRIMARY KEY (product_id, category_id),

    CONSTRAINT fk_product_category_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_product_category_category
        FOREIGN KEY (category_id)
        REFERENCES category(category_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 8. PRODUCT VARIANT
-- ============================================================

CREATE TABLE product_variant (
    variant_id BIGINT UNSIGNED AUTO_INCREMENT,
    product_id BIGINT UNSIGNED NOT NULL,
    sku VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,

    CONSTRAINT pk_product_variant
        PRIMARY KEY (variant_id),

    CONSTRAINT uq_product_variant_sku
        UNIQUE (sku),

    CONSTRAINT fk_product_variant_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_product_variant_price
        CHECK (price >= 0)
);


-- ============================================================
-- 9. ATTRIBUTE
-- ============================================================

CREATE TABLE attribute (
    attribute_id BIGINT UNSIGNED AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,

    CONSTRAINT pk_attribute
        PRIMARY KEY (attribute_id),

    CONSTRAINT uq_attribute_name
        UNIQUE (name)
);


-- ============================================================
-- 10. ATTRIBUTE VALUE
-- ============================================================

CREATE TABLE attribute_value (
    attribute_value_id BIGINT UNSIGNED AUTO_INCREMENT,
    attribute_id BIGINT UNSIGNED NOT NULL,
    value VARCHAR(100) NOT NULL,

    CONSTRAINT pk_attribute_value
        PRIMARY KEY (attribute_value_id),

    CONSTRAINT uq_attribute_value
        UNIQUE (attribute_id, value),

    CONSTRAINT fk_attribute_value_attribute
        FOREIGN KEY (attribute_id)
        REFERENCES attribute(attribute_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 11. PRODUCT VARIANT <-> ATTRIBUTE VALUE
-- ============================================================

CREATE TABLE variant_attribute (
    variant_id BIGINT UNSIGNED,
    attribute_value_id BIGINT UNSIGNED,

    CONSTRAINT pk_variant_attribute
        PRIMARY KEY (variant_id, attribute_value_id),

    CONSTRAINT fk_variant_attribute_variant
        FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_variant_attribute_value
        FOREIGN KEY (attribute_value_id)
        REFERENCES attribute_value(attribute_value_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 12. PRODUCT IMAGE
-- ============================================================

CREATE TABLE product_image (
    image_id BIGINT UNSIGNED AUTO_INCREMENT,
    product_id BIGINT UNSIGNED NOT NULL,
    image_url VARCHAR(500) NOT NULL,
    display_order INT UNSIGNED NOT NULL DEFAULT 1,

    CONSTRAINT pk_product_image
        PRIMARY KEY (image_id),

    CONSTRAINT fk_product_image_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 13. CART
-- ============================================================

CREATE TABLE cart (
    cart_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_cart
        PRIMARY KEY (cart_id),

    CONSTRAINT uq_cart_user
        UNIQUE (user_id),

    CONSTRAINT fk_cart_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 14. CART ITEM
-- ============================================================

CREATE TABLE cart_item (
    cart_id BIGINT UNSIGNED,
    variant_id BIGINT UNSIGNED,
    quantity INT UNSIGNED NOT NULL,

    CONSTRAINT pk_cart_item
        PRIMARY KEY (cart_id, variant_id),

    CONSTRAINT fk_cart_item_cart
        FOREIGN KEY (cart_id)
        REFERENCES cart(cart_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_cart_item_variant
        FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_cart_item_quantity
        CHECK (quantity > 0)
);


-- ============================================================
-- 15. WISHLIST
-- ============================================================

CREATE TABLE wishlist (
    wishlist_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_wishlist
        PRIMARY KEY (wishlist_id),

    CONSTRAINT uq_wishlist_user
        UNIQUE (user_id),

    CONSTRAINT fk_wishlist_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 16. WISHLIST ITEM
-- ============================================================

CREATE TABLE wishlist_item (
    wishlist_id BIGINT UNSIGNED,
    variant_id BIGINT UNSIGNED,
    added_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_wishlist_item
        PRIMARY KEY (wishlist_id, variant_id),

    CONSTRAINT fk_wishlist_item_wishlist
        FOREIGN KEY (wishlist_id)
        REFERENCES wishlist(wishlist_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_wishlist_item_variant
        FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 17. INVENTORY
-- ============================================================

CREATE TABLE inventory (
    inventory_id BIGINT UNSIGNED AUTO_INCREMENT,
    variant_id BIGINT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL DEFAULT 0,
    reorder_level INT UNSIGNED NOT NULL DEFAULT 5,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_inventory
        PRIMARY KEY (inventory_id),

    CONSTRAINT uq_inventory_variant
        UNIQUE (variant_id),

    CONSTRAINT fk_inventory_variant
        FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 18. INVENTORY TRANSACTION
-- ============================================================

CREATE TABLE inventory_transaction (
    transaction_id BIGINT UNSIGNED AUTO_INCREMENT,
    inventory_id BIGINT UNSIGNED NOT NULL,
    transaction_type ENUM(
        'PURCHASE',
        'RESTOCK',
        'RETURN',
        'ADJUSTMENT'
    ) NOT NULL,
    quantity INT NOT NULL,
    reference_type VARCHAR(50),
    reference_id BIGINT UNSIGNED,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_inventory_transaction
        PRIMARY KEY (transaction_id),

    CONSTRAINT fk_inventory_transaction_inventory
        FOREIGN KEY (inventory_id)
        REFERENCES inventory(inventory_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_inventory_transaction_quantity
        CHECK (quantity <> 0)
);


-- ============================================================
-- 19. ORDERS
-- ============================================================

CREATE TABLE orders (
    order_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    shipping_address_id BIGINT UNSIGNED NOT NULL,
    order_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status ENUM(
        'PENDING',
        'CONFIRMED',
        'PROCESSING',
        'SHIPPED',
        'DELIVERED',
        'CANCELLED',
        'RETURNED'
    ) NOT NULL DEFAULT 'PENDING',
    total_amount DECIMAL(10,2) NOT NULL,

    CONSTRAINT pk_orders
        PRIMARY KEY (order_id),

    CONSTRAINT fk_orders_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id),

    CONSTRAINT fk_orders_shipping_address
        FOREIGN KEY (shipping_address_id)
        REFERENCES address(address_id),

    CONSTRAINT chk_orders_total
        CHECK (total_amount >= 0)
);


-- ============================================================
-- 20. ORDER ITEM
-- ============================================================

CREATE TABLE order_item (
    order_item_id BIGINT UNSIGNED AUTO_INCREMENT,
    order_id BIGINT UNSIGNED NOT NULL,
    variant_id BIGINT UNSIGNED NOT NULL,
    quantity INT UNSIGNED NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,

    CONSTRAINT pk_order_item
        PRIMARY KEY (order_item_id),

    CONSTRAINT fk_order_item_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_order_item_variant
        FOREIGN KEY (variant_id)
        REFERENCES product_variant(variant_id),

    CONSTRAINT chk_order_item_quantity
        CHECK (quantity > 0),

    CONSTRAINT chk_order_item_price
        CHECK (unit_price >= 0)
);


-- ============================================================
-- 21. PAYMENT
-- ============================================================

CREATE TABLE payment (
    payment_id BIGINT UNSIGNED AUTO_INCREMENT,
    order_id BIGINT UNSIGNED NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    payment_method ENUM(
        'CARD',
        'UPI',
        'NET_BANKING',
        'COD'
    ) NOT NULL,
    payment_status ENUM(
        'PENDING',
        'SUCCESS',
        'FAILED',
        'REFUNDED'
    ) NOT NULL DEFAULT 'PENDING',
    transaction_ref VARCHAR(150),
    paid_at DATETIME,

    CONSTRAINT pk_payment
        PRIMARY KEY (payment_id),

    CONSTRAINT uq_payment_order
        UNIQUE (order_id),

    CONSTRAINT fk_payment_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_payment_amount
        CHECK (amount >= 0)
);


-- ============================================================
-- 22. SHIPMENT
-- ============================================================

CREATE TABLE shipment (
    shipment_id BIGINT UNSIGNED AUTO_INCREMENT,
    order_id BIGINT UNSIGNED NOT NULL,
    carrier VARCHAR(100),
    tracking_number VARCHAR(150),
    shipment_status ENUM(
        'PENDING',
        'SHIPPED',
        'IN_TRANSIT',
        'DELIVERED',
        'FAILED'
    ) NOT NULL DEFAULT 'PENDING',
    shipped_at DATETIME,
    delivered_at DATETIME,

    CONSTRAINT pk_shipment
        PRIMARY KEY (shipment_id),

    CONSTRAINT uq_shipment_order
        UNIQUE (order_id),

    CONSTRAINT fk_shipment_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 23. ORDER STATUS HISTORY
-- ============================================================

CREATE TABLE order_status_history (
    history_id BIGINT UNSIGNED AUTO_INCREMENT,
    order_id BIGINT UNSIGNED NOT NULL,
    old_status VARCHAR(30),
    new_status VARCHAR(30) NOT NULL,
    changed_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_order_status_history
        PRIMARY KEY (history_id),

    CONSTRAINT fk_order_status_history_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE
);


-- ============================================================
-- 24. REVIEW
-- ============================================================

CREATE TABLE review (
    review_id BIGINT UNSIGNED AUTO_INCREMENT,
    user_id BIGINT UNSIGNED NOT NULL,
    product_id BIGINT UNSIGNED NOT NULL,
    rating TINYINT UNSIGNED NOT NULL,
    comment TEXT,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_review
        PRIMARY KEY (review_id),

    CONSTRAINT uq_review_user_product
        UNIQUE (user_id, product_id),

    CONSTRAINT fk_review_user
        FOREIGN KEY (user_id)
        REFERENCES users(user_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_review_product
        FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE,

    CONSTRAINT chk_review_rating
        CHECK (rating BETWEEN 1 AND 5)
);


-- ============================================================
-- 25. COUPON
-- ============================================================

CREATE TABLE coupon (
    coupon_id BIGINT UNSIGNED AUTO_INCREMENT,
    code VARCHAR(50) NOT NULL,
    discount_type ENUM('PERCENTAGE', 'FIXED') NOT NULL,
    discount_value DECIMAL(10,2) NOT NULL,
    minimum_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
    start_date DATETIME NOT NULL,
    expiry_date DATETIME NOT NULL,
    usage_limit INT UNSIGNED,

    CONSTRAINT pk_coupon
        PRIMARY KEY (coupon_id),

    CONSTRAINT uq_coupon_code
        UNIQUE (code),

    CONSTRAINT chk_coupon_discount
        CHECK (discount_value > 0),

    CONSTRAINT chk_coupon_minimum
        CHECK (minimum_amount >= 0),

    CONSTRAINT chk_coupon_dates
        CHECK (expiry_date > start_date)
);


-- ============================================================
-- 26. ORDER <-> COUPON
-- ============================================================

CREATE TABLE order_coupon (
    order_id BIGINT UNSIGNED,
    coupon_id BIGINT UNSIGNED,
    discount_amount DECIMAL(10,2) NOT NULL,

    CONSTRAINT pk_order_coupon
        PRIMARY KEY (order_id, coupon_id),

    CONSTRAINT fk_order_coupon_order
        FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
        ON DELETE CASCADE,

    CONSTRAINT fk_order_coupon_coupon
        FOREIGN KEY (coupon_id)
        REFERENCES coupon(coupon_id),

    CONSTRAINT chk_order_coupon_discount
        CHECK (discount_amount >= 0)
);


-- ============================================================
-- 27. RETURN REQUEST
-- ============================================================

CREATE TABLE return_request (
    return_id BIGINT UNSIGNED AUTO_INCREMENT,
    order_item_id BIGINT UNSIGNED NOT NULL,
    reason VARCHAR(500) NOT NULL,
    status ENUM(
        'REQUESTED',
        'APPROVED',
        'REJECTED',
        'RECEIVED',
        'COMPLETED'
    ) NOT NULL DEFAULT 'REQUESTED',
    requested_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at DATETIME,

    CONSTRAINT pk_return_request
        PRIMARY KEY (return_id),

    CONSTRAINT fk_return_request_order_item
        FOREIGN KEY (order_item_id)
        REFERENCES order_item(order_item_id)
);


-- ============================================================
-- 28. REFUND
-- ============================================================

CREATE TABLE refund (
    refund_id BIGINT UNSIGNED AUTO_INCREMENT,
    return_id BIGINT UNSIGNED NOT NULL,
    payment_id BIGINT UNSIGNED NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    refund_status ENUM(
        'PENDING',
        'PROCESSED',
        'FAILED'
    ) NOT NULL DEFAULT 'PENDING',
    refunded_at DATETIME,

    CONSTRAINT pk_refund
        PRIMARY KEY (refund_id),

    CONSTRAINT uq_refund_return
        UNIQUE (return_id),

    CONSTRAINT fk_refund_return
        FOREIGN KEY (return_id)
        REFERENCES return_request(return_id),

    CONSTRAINT fk_refund_payment
        FOREIGN KEY (payment_id)
        REFERENCES payment(payment_id),

    CONSTRAINT chk_refund_amount
        CHECK (amount >= 0)
);
