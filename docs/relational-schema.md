# Relational Schema

## Database

**Database Name:** `ecommerce_marketplace`

**DBMS:** MySQL 8.0+

## 1. Users and Authentication

### USERS

* `user_id` — Primary Key
* `name` — User's name
* `email` — Unique email address
* `password_hash` — Hashed authentication password
* `phone` — Contact number
* `role` — CUSTOMER / SELLER / ADMIN
* `created_at` — Account creation timestamp

### SELLER_PROFILE

* `user_id` — Primary Key, Foreign Key → USERS(user_id)
* `store_name` — Seller's store name
* `business_name` — Seller's business name

### ADDRESS

* `address_id` — Primary Key
* `user_id` — Foreign Key → USERS(user_id)
* `address_line1`
* `address_line2`
* `city`
* `state`
* `postal_code`
* `country`
* `address_type`

## 2. Product Catalogue

### BRAND

* `brand_id` — Primary Key
* `name` — Unique brand name

### CATEGORY

* `category_id` — Primary Key
* `name` — Unique category name

### PRODUCT

* `product_id` — Primary Key
* `seller_id` — Foreign Key → SELLER_PROFILE(user_id)
* `brand_id` — Foreign Key → BRAND(brand_id)
* `name`
* `description`
* `status`
* `created_at`

### PRODUCT_CATEGORY

* `product_id` — Primary Key, Foreign Key → PRODUCT(product_id)
* `category_id` — Primary Key, Foreign Key → CATEGORY(category_id)

This relation resolves the many-to-many relationship between products and categories.

### PRODUCT_VARIANT

* `variant_id` — Primary Key
* `product_id` — Foreign Key → PRODUCT(product_id)
* `sku` — Unique stock keeping unit
* `price`

### ATTRIBUTE

* `attribute_id` — Primary Key
* `name` — Unique attribute name

Examples include Color, Size, RAM and Storage.

### ATTRIBUTE_VALUE

* `attribute_value_id` — Primary Key
* `attribute_id` — Foreign Key → ATTRIBUTE(attribute_id)
* `value`

### VARIANT_ATTRIBUTE

* `variant_id` — Primary Key, Foreign Key → PRODUCT_VARIANT(variant_id)
* `attribute_value_id` — Primary Key, Foreign Key → ATTRIBUTE_VALUE(attribute_value_id)

This relation resolves the many-to-many relationship between product variants and attribute values.

### PRODUCT_IMAGE

* `image_id` — Primary Key
* `product_id` — Foreign Key → PRODUCT(product_id)
* `image_url`
* `display_order`

## 3. Cart and Wishlist

### CART

* `cart_id` — Primary Key
* `user_id` — Unique Foreign Key → USERS(user_id)
* `created_at`
* `updated_at`

A user has at most one cart.

### CART_ITEM

* `cart_id` — Primary Key, Foreign Key → CART(cart_id)
* `variant_id` — Primary Key, Foreign Key → PRODUCT_VARIANT(variant_id)
* `quantity`

### WISHLIST

* `wishlist_id` — Primary Key
* `user_id` — Unique Foreign Key → USERS(user_id)
* `created_at`

A user has at most one wishlist.

### WISHLIST_ITEM

* `wishlist_id` — Primary Key, Foreign Key → WISHLIST(wishlist_id)
* `variant_id` — Primary Key, Foreign Key → PRODUCT_VARIANT(variant_id)
* `added_at`

## 4. Inventory

### INVENTORY

* `inventory_id` — Primary Key
* `variant_id` — Unique Foreign Key → PRODUCT_VARIANT(variant_id)
* `quantity`
* `reorder_level`
* `updated_at`

Each product variant has one inventory record.

### INVENTORY_TRANSACTION

* `transaction_id` — Primary Key
* `inventory_id` — Foreign Key → INVENTORY(inventory_id)
* `transaction_type`
* `quantity`
* `reference_type`
* `reference_id`
* `created_at`

Transaction types include PURCHASE, RESTOCK, RETURN and ADJUSTMENT.

## 5. Orders and Payments

### ORDERS

* `order_id` — Primary Key
* `user_id` — Foreign Key → USERS(user_id)
* `shipping_address_id` — Foreign Key → ADDRESS(address_id)
* `order_date`
* `status`
* `total_amount`

### ORDER_ITEM

* `order_item_id` — Primary Key
* `order_id` — Foreign Key → ORDERS(order_id)
* `variant_id` — Foreign Key → PRODUCT_VARIANT(variant_id)
* `quantity`
* `unit_price`

`unit_price` stores the price at the time of purchase rather than relying on the product's current price.

### PAYMENT

* `payment_id` — Primary Key
* `order_id` — Unique Foreign Key → ORDERS(order_id)
* `amount`
* `payment_method`
* `payment_status`
* `transaction_ref`
* `paid_at`

### SHIPMENT

* `shipment_id` — Primary Key
* `order_id` — Unique Foreign Key → ORDERS(order_id)
* `carrier`
* `tracking_number`
* `shipment_status`
* `shipped_at`
* `delivered_at`

### ORDER_STATUS_HISTORY

* `history_id` — Primary Key
* `order_id` — Foreign Key → ORDERS(order_id)
* `old_status`
* `new_status`
* `changed_at`

This table will later be populated automatically using a database trigger when an order's status changes.

## 6. Reviews

### REVIEW

* `review_id` — Primary Key
* `user_id` — Foreign Key → USERS(user_id)
* `product_id` — Foreign Key → PRODUCT(product_id)
* `rating`
* `comment`
* `created_at`

A unique constraint on `(user_id, product_id)` prevents a user from submitting multiple reviews for the same product.

The rating is restricted to values from 1 to 5.

## 7. Coupons

### COUPON

* `coupon_id` — Primary Key
* `code` — Unique coupon code
* `discount_type`
* `discount_value`
* `minimum_amount`
* `start_date`
* `expiry_date`
* `usage_limit`

### ORDER_COUPON

* `order_id` — Primary Key, Foreign Key → ORDERS(order_id)
* `coupon_id` — Foreign Key → COUPON(coupon_id)
* `discount_amount`

This relation associates coupons with orders.

## 8. Returns and Refunds

### RETURN_REQUEST

* `return_id` — Primary Key
* `order_item_id` — Foreign Key → ORDER_ITEM(order_item_id)
* `reason`
* `status`
* `requested_at`
* `resolved_at`

### REFUND

* `refund_id` — Primary Key
* `return_id` — Unique Foreign Key → RETURN_REQUEST(return_id)
* `payment_id` — Foreign Key → PAYMENT(payment_id)
* `amount`
* `refund_status`
* `refunded_at`

## 9. Major Relationships

* USERS 1:N ADDRESS
* USERS 1:0..1 SELLER_PROFILE
* SELLER_PROFILE 1:N PRODUCT
* BRAND 1:N PRODUCT
* PRODUCT M:N CATEGORY through PRODUCT_CATEGORY
* PRODUCT 1:N PRODUCT_VARIANT
* PRODUCT 1:N PRODUCT_IMAGE
* ATTRIBUTE 1:N ATTRIBUTE_VALUE
* PRODUCT_VARIANT M:N ATTRIBUTE_VALUE through VARIANT_ATTRIBUTE
* USERS 1:0..1 CART
* CART M:N PRODUCT_VARIANT through CART_ITEM
* USERS 1:0..1 WISHLIST
* WISHLIST M:N PRODUCT_VARIANT through WISHLIST_ITEM
* PRODUCT_VARIANT 1:1 INVENTORY
* INVENTORY 1:N INVENTORY_TRANSACTION
* USERS 1:N ORDERS
* ORDERS 1:N ORDER_ITEM
* ORDERS 1:0..1 PAYMENT
* ORDERS 1:0..1 SHIPMENT
* ORDERS 1:N ORDER_STATUS_HISTORY
* USERS 1:N REVIEW
* PRODUCT 1:N REVIEW
* ORDERS M:N COUPON through ORDER_COUPON
* ORDER_ITEM 1:N RETURN_REQUEST
* RETURN_REQUEST 1:0..1 REFUND
* PAYMENT 1:N REFUND
