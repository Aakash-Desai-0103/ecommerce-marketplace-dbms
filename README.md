# E-Commerce Marketplace DBMS

A database-driven multi-seller e-commerce marketplace built for the Database Management Systems course (UE23CS351A).
Transactional data (users, catalogue, inventory, orders, payments, returns) is stored in **MySQL**; flexible and
read-heavy data (product specifications, reviews, search, recently viewed products and recommendations) is stored in **MongoDB**.

**Team:** Aakash Desai (PES1UG24CS006) · Anagha B Poojari(PES1UG24CS056)

**Status:** Phase 1 (database design and implementation) complete. Next phase: Next.js frontend, API layer and role-based authentication.

---

## Tech stack

| Layer | Technology |
|---|---|
| Relational database | MySQL 8.0+ |
| Document database | MongoDB 6.0+ (local) with `mongosh` |
| Application (next phase) | Next.js, API route handlers |

---

## Repository structure

```
ecommerce-marketplace-dbms/
├── database/
│   ├── schema.sql                     # DDL: 28 tables with PK, FK, UNIQUE, CHECK constraints
│   ├── seed.sql                       # Sample data: >= 5 rows per table, fully reconciled
│   ├── queries.sql                    # Week 1: DDL/DML, joins, aggregates, relational algebra
│   ├── week2_queries.sql              # Set operations, joins, nested queries, NULLs, modification
│   ├── week3_database_objects.sql     # Views, roles & users, triggers
│   ├── week3_queries.sql              # Correlated and nested queries
│   ├── week4.sql                      # Functions, transactional procedures, CTEs (incl. recursive)
│   ├── week5_window_search.sql        # Window functions, FULLTEXT search
│   ├── unit3_query_optimization.sql   # EXPLAIN, indexing, optimizer behaviour
│   ├── unit3_normalization.sql        # FDs, 1NF → 2NF → 3NF → BCNF → 4NF, lossless joins
│   └── week6.sql                      # Transactions, ACID, serializability, locking, deadlock
├── mongodb/
│   └── ecommerce_mongo.js             # Collections, validation, indexes, 4 NoSQL features
└── docs/
    ├── ER_diagram.pdf
    ├── Relational_schema.pdf
    └── relational-schema.md
```

---

## Setup and run

### Prerequisites
- MySQL 8.0 or newer (`mysql` client on PATH)
- MongoDB 6.0 or newer running locally, and MongoDB Shell (`mongosh`)

### 1. MySQL

Open a terminal **inside the `database/` folder** and log in as root (root is needed because Week 3 creates database users and roles):

```bash
mysql -u root -p
```

Then run the files **in this order**. The order matters: the seed data must be loaded before the Week 3 triggers.

```sql
DROP DATABASE IF EXISTS ecommerce_marketplace;   -- start clean
SOURCE schema.sql
SOURCE seed.sql
SOURCE queries.sql
SOURCE week2_queries.sql
SOURCE week3_database_objects.sql
SOURCE week3_queries.sql
SOURCE week4.sql
SOURCE week5_window_search.sql
SOURCE unit3_query_optimization.sql
SOURCE unit3_normalization.sql
SOURCE week6.sql
```

All files can be re-run; repeat the full sequence for a clean state.

### 2. MongoDB

Make sure the MongoDB service is running, then from the `mongodb/` folder:

```bash
mongosh "mongodb://localhost:27017" ecommerce_mongo.js
```

The script drops and rebuilds its collections on every run.

---

## Verifying the setup

**MySQL**

```sql
USE ecommerce_marketplace;

-- 28 tables
SELECT COUNT(*) FROM information_schema.tables
WHERE table_schema = 'ecommerce_marketplace' AND table_type = 'BASE TABLE';
```

- `week6.sql` ends with a test report: **16 passed, 0 failed**.
- Every consistency audit in `week6.sql` returns an empty set (except the low-stock list).
- Every lossless-join check in `unit3_normalization.sql` returns `0`.

**MongoDB** — the script output should start with
`Seeded: 7 products, 6 reviews, 19 view events, 6 recently-viewed lists`,
show four `Rejected (...)` validation lines, `IXSCAN` at step 3.8, and end with `Done.`

---

## Features implemented

### MySQL
- **Schema:** 28 normalized tables (BCNF) covering users, sellers, catalogue, variants, attributes, inventory with a stock ledger, cart, wishlist, orders, payments, shipments, status history, reviews, coupons, returns and refunds.
- **Integrity:** named primary/foreign keys, UNIQUE and CHECK constraints, ENUMs, and triggers that validate and track stock.
- **Advanced SQL:** 4 views, 4 triggers, 4 functions, transactional stored procedures, CTEs (including recursive), window functions, FULLTEXT search, database roles with least-privilege grants.
- **Transactions:** atomic order placement with `SELECT ... FOR UPDATE`; 16 automated tests covering atomicity, consistency, isolation, durability and serializability; two-session demos of lost update, isolation levels and deadlock.
- **Design theory:** functional dependency checks, normalization to BCNF/4NF with lossless-join verification, query optimization with `EXPLAIN`.

### MongoDB
| Feature | Collection(s) |
|---|---|
| Product features / specifications (flexible per product type) | `product_catalog` |
| Product reviews (pros/cons, photos, helpful votes, seller replies) | `product_reviews` |
| Product search and filtering (text search, filters, facets) | `product_catalog` |
| Recently viewed products and recommendations | `product_view_events`, `user_recently_viewed` |

All collections use `$jsonSchema` validation; indexes include text, compound, multikey, unique and TTL.

### Why two databases
MySQL guarantees ACID transactions and referential integrity for money and stock. MongoDB stores data whose structure
varies by product type and is read far more often than it changes. Both databases share the same identifiers
(`product_id`, `user_id`, `order_id`, `review_id`), so the application can combine their results.

---

## Demo accounts

| Purpose | Credentials |
|---|---|
| Application users (seed data) | any seeded email, password `Password@123` (stored as bcrypt hashes) |
| MySQL role demo: customer | `customer_user` / `Customer@123` |
| MySQL role demo: seller | `seller_user` / `Seller@123` |
| MySQL role demo: admin | `admin_user` / `Admin@123` |

These are demo-only credentials for local coursework. The application will read its database credentials from a `.env` file, which is not committed.

---

## Roadmap (next phase)
- [ ] Next.js frontend for customers, sellers and admins
- [ ] API route handlers connecting to MySQL and MongoDB
- [ ] Login with bcrypt verification and role-based access
- [ ] `.env` configuration and `.env.example`
- [ ] Application screenshots and end-to-end testing