// =====================================================================
// E-COMMERCE MARKETPLACE — MongoDB (NoSQL) COMPONENT
// MongoDB 6.0+ Community (local), run with mongosh:
//
//   mongosh "mongodb://localhost:27017" ecommerce_mongo.js
//   (or, inside mongosh:  load("ecommerce_mongo.js") )
//
// Safe to re-run: every collection is dropped and rebuilt.
//
// WHAT LIVES WHERE
//   MySQL   — users, sellers, orders, payments, inventory, prices,
//             and the review row (rating + who/what, for integrity).
//   MongoDB — data whose shape varies or is read-heavy:
//     1. product_catalog        flexible specifications per product type
//     2. product_reviews        rich review content (text, pros/cons,
//                               photos, helpful votes, seller replies)
//     3. product_view_events    raw "viewed" events (auto-expire via TTL)
//        user_recently_viewed   last 10 products per user
//   Search, filtering and recommendations run on these collections.
//   Section 5 adds VECTOR (semantic) SEARCH: each product stores a
//   384-dimensional text embedding and is ranked by cosine similarity.
//
// LINKING: product_id, user_id, seller_id, order_id and review_id are the
// MySQL primary keys, so the application can join results across both.
// Prices in product_catalog are a read copy of product_variant.price,
// kept for filtering; MySQL remains the source of truth for price/stock.
// =====================================================================

db = db.getSiblingDB("ecommerce_marketplace");

function show(title, result) {
    print("\n========== " + title + " ==========");
    const rows = Array.isArray(result) ? result : result.toArray();
    if (rows.length === 0) print("(no results)");
    rows.forEach(r => printjson(r));
}

const hoursAgo = h => new Date(Date.now() - h * 60 * 60 * 1000);


// =====================================================================
// 0. RESET
// =====================================================================

["product_catalog", "product_reviews", "product_view_events", "user_recently_viewed"]
    .forEach(name => db.getCollection(name).drop());


// =====================================================================
// 1. COLLECTIONS WITH SCHEMA VALIDATION (database-level integrity)
// =====================================================================

// 1.1 product_catalog — common fields are enforced; `specifications`
// is deliberately free-form because a phone, a shoe and a shelf have
// completely different attributes.
db.createCollection("product_catalog", {
    validator: {
        $and: [
            {
                $jsonSchema: {
                    bsonType: "object",
                    required: ["product_id", "name", "brand", "seller", "categories",
                               "status", "variants", "price", "specifications"],
                    properties: {
                        product_id:     { bsonType: "int", minimum: 1 },
                        name:           { bsonType: "string", minLength: 1 },
                        brand:          { bsonType: "string" },
                        description:    { bsonType: "string" },
                        status:         { enum: ["ACTIVE", "INACTIVE", "DISCONTINUED"] },
                        categories:     { bsonType: "array", minItems: 1, items: { bsonType: "string" } },
                        tags:           { bsonType: "array", items: { bsonType: "string" } },
                        specifications: { bsonType: "object" },
                        seller: {
                            bsonType: "object",
                            required: ["seller_id", "store_name"],
                            properties: {
                                seller_id:  { bsonType: "int" },
                                store_name: { bsonType: "string" }
                            }
                        },
                        variants: {
                            bsonType: "array",
                            minItems: 1,
                            items: {
                                bsonType: "object",
                                required: ["variant_id", "sku", "price"],
                                properties: {
                                    variant_id: { bsonType: "int" },
                                    sku:        { bsonType: "string" },
                                    price:      { bsonType: ["double", "int", "decimal"], minimum: 0 },
                                    attributes: { bsonType: "object" }
                                }
                            }
                        },
                        price: {
                            bsonType: "object",
                            required: ["min", "max"],
                            properties: {
                                min: { bsonType: ["double", "int", "decimal"], minimum: 0 },
                                max: { bsonType: ["double", "int", "decimal"], minimum: 0 }
                            }
                        },
                        rating: {
                            bsonType: "object",
                            properties: {
                                average: { bsonType: ["double", "int"], minimum: 0, maximum: 5 },
                                count:   { bsonType: "int", minimum: 0 }
                            }
                        },
                        // Optional: text embedding for vector search (section 5)
                        embedding: {
                            bsonType: "array",
                            minItems: 384,
                            maxItems: 384,
                            items: { bsonType: ["double", "int"], minimum: -1, maximum: 1 }
                        },
                        embedding_model: { bsonType: "string" }
                    }
                }
            },
            // Cross-field rule that $jsonSchema alone cannot express
            { $expr: { $lte: ["$price.min", "$price.max"] } }
        ]
    },
    validationAction: "error"
});

// 1.2 product_reviews
db.createCollection("product_reviews", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["review_id", "product_id", "user", "rating", "body", "created_at"],
            properties: {
                review_id:         { bsonType: "int" },
                product_id:        { bsonType: "int" },
                user: {
                    bsonType: "object",
                    required: ["user_id", "name"],
                    properties: {
                        user_id: { bsonType: "int" },
                        name:    { bsonType: "string" }
                    }
                },
                rating:            { bsonType: "int", minimum: 1, maximum: 5 },
                title:             { bsonType: "string", maxLength: 100 },
                body:              { bsonType: "string", minLength: 10, maxLength: 2000 },
                pros:              { bsonType: "array", items: { bsonType: "string" } },
                cons:              { bsonType: "array", items: { bsonType: "string" } },
                images:            { bsonType: "array", maxItems: 5, items: { bsonType: "string" } },
                verified_purchase: { bsonType: "bool" },
                helpful: {
                    bsonType: "object",
                    properties: {
                        count:  { bsonType: "int", minimum: 0 },
                        voters: { bsonType: "array", items: { bsonType: "int" } }
                    }
                },
                seller_reply: {
                    bsonType: "object",
                    required: ["text", "replied_at"],
                    properties: {
                        text:       { bsonType: "string" },
                        replied_at: { bsonType: "date" }
                    }
                },
                created_at:        { bsonType: "date" }
            }
        }
    }
});

// 1.3 product_view_events — one document per product view
db.createCollection("product_view_events", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["user_id", "product_id", "viewed_at"],
            properties: {
                user_id:    { bsonType: "int" },
                product_id: { bsonType: "int" },
                viewed_at:  { bsonType: "date" },
                source:     { enum: ["search", "home", "recommendation", "category", "direct"] }
            }
        }
    }
});

// 1.4 user_recently_viewed — one document per user, newest first, max 10
db.createCollection("user_recently_viewed", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            required: ["user_id", "items"],
            properties: {
                user_id: { bsonType: "int" },
                items: {
                    bsonType: "array",
                    maxItems: 10,
                    items: {
                        bsonType: "object",
                        required: ["product_id", "viewed_at"],
                        properties: {
                            product_id: { bsonType: "int" },
                            viewed_at:  { bsonType: "date" }
                        }
                    }
                }
            }
        }
    }
});


// =====================================================================
// 2. INDEXES
// =====================================================================

// Catalog
db.product_catalog.createIndex({ product_id: 1 }, { unique: true });
db.product_catalog.createIndex(
    { name: "text", brand: "text", tags: "text", categories: "text", description: "text" },
    {
        name: "catalog_text_search",
        weights: { name: 10, brand: 6, tags: 5, categories: 3, description: 2 },
        default_language: "english"
    }
);
db.product_catalog.createIndex({ categories: 1, "price.min": 1 });   // multikey: filter by category, sort by price
db.product_catalog.createIndex({ brand: 1, "price.min": 1 });
db.product_catalog.createIndex({ "rating.average": -1 });
db.product_catalog.createIndex({ "variants.attributes.size": 1 });   // multikey on embedded array
db.product_catalog.createIndex({ tags: 1 });

// Reviews
db.product_reviews.createIndex({ review_id: 1 }, { unique: true });
db.product_reviews.createIndex({ product_id: 1, "user.user_id": 1 }, { unique: true }); // one review per user per product
db.product_reviews.createIndex({ product_id: 1, "helpful.count": -1 });
db.product_reviews.createIndex({ product_id: 1, created_at: -1 });

// Views
db.product_view_events.createIndex({ product_id: 1, user_id: 1 });
db.product_view_events.createIndex({ user_id: 1, viewed_at: -1 });
db.product_view_events.createIndex(
    { viewed_at: 1 },
    { expireAfterSeconds: 60 * 60 * 24 * 90, name: "ttl_90_days" }   // events auto-delete after 90 days
);
db.user_recently_viewed.createIndex({ user_id: 1 }, { unique: true });


// =====================================================================
// 3. SEED DATA (ids match the MySQL seed)
// =====================================================================

db.product_catalog.insertMany([
    {
        product_id: 1,
        name: "iPhone 16",
        brand: "Apple",
        seller: { seller_id: 5, store_name: "TechWorld" },
        categories: ["Electronics", "Smartphones"],
        description: "Latest Apple smartphone",
        tags: ["apple", "iphone", "smartphone", "5g", "ios", "camera"],
        status: "ACTIVE",
        specifications: {
            display: { size_in: 6.1, type: "Super Retina XDR OLED", refresh_hz: 60 },
            processor: "A18",
            ram_gb: 8,
            rear_camera_mp: 48,
            battery_mah: 3561,
            os: "iOS 18",
            connectivity_5g: true,
            weight_g: 170
        },
        variants: [
            { variant_id: 1, sku: "IPH16-128-BLK", price: 69999, attributes: { storage: "128GB", color: "Black" } },
            { variant_id: 2, sku: "IPH16-256-BLK", price: 79999, attributes: { storage: "256GB", color: "Black" } }
        ],
        price: { min: 69999, max: 79999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 2,
        name: "Galaxy S25",
        brand: "Samsung",
        seller: { seller_id: 5, store_name: "TechWorld" },
        categories: ["Electronics", "Smartphones"],
        description: "Samsung flagship smartphone",
        tags: ["samsung", "galaxy", "smartphone", "5g", "android", "camera"],
        status: "ACTIVE",
        specifications: {
            display: { size_in: 6.2, type: "Dynamic AMOLED 2X", refresh_hz: 120 },
            processor: "Snapdragon 8 Elite",
            ram_gb: 12,
            rear_camera_mp: 50,
            battery_mah: 4000,
            os: "Android 15",
            connectivity_5g: true,
            weight_g: 162
        },
        variants: [
            { variant_id: 3, sku: "S25-128-BLK", price: 74999, attributes: { storage: "128GB", color: "Black" } },
            { variant_id: 4, sku: "S25-256-BLK", price: 84999, attributes: { storage: "256GB", color: "Black" } }
        ],
        price: { min: 74999, max: 84999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 3,
        name: "MX Master 3S",
        brand: "Logitech",
        seller: { seller_id: 5, store_name: "TechWorld" },
        categories: ["Electronics", "Accessories"],
        description: "Wireless productivity mouse",
        tags: ["logitech", "mouse", "wireless", "productivity", "office"],
        status: "ACTIVE",
        specifications: {
            connectivity: ["Bluetooth", "Logi Bolt USB receiver"],
            max_dpi: 8000,
            buttons: 7,
            battery: "Rechargeable, up to 70 days",
            compatible_os: ["Windows", "macOS", "Linux"],
            weight_g: 141
        },
        variants: [
            { variant_id: 5, sku: "MX3S-BLK", price: 8495, attributes: { color: "Black" } }
        ],
        price: { min: 8495, max: 8495 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 4,
        name: "MacBook Air M4",
        brand: "Apple",
        seller: { seller_id: 5, store_name: "TechWorld" },
        categories: ["Electronics", "Laptops"],
        description: "Lightweight Apple laptop",
        tags: ["apple", "macbook", "laptop", "ultrabook", "macos", "productivity"],
        status: "ACTIVE",
        specifications: {
            display: { size_in: 13.6, type: "Liquid Retina" },
            processor: "Apple M4",
            ram_gb: 16,
            storage_gb: 512,
            battery_hours: 18,
            os: "macOS",
            weight_kg: 1.24
        },
        variants: [
            { variant_id: 6, sku: "MBA-M4-16-512", price: 114999, attributes: { storage: "512GB", ram: "16GB" } }
        ],
        price: { min: 114999, max: 114999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 5,
        name: "Air Max 270",
        brand: "Nike",
        seller: { seller_id: 6, store_name: "FashionHub" },
        categories: ["Fashion", "Footwear"],
        description: "Nike lifestyle running shoe",
        tags: ["nike", "sneakers", "running", "lifestyle", "shoes"],
        status: "ACTIVE",
        specifications: {
            upper: "Mesh",
            sole: "Rubber",
            cushioning: "Max Air unit",
            closure: "Lace-up",
            usage: ["Lifestyle", "Running"],
            gender: "Men"
        },
        variants: [
            { variant_id: 7, sku: "AM270-BLK-9",  price: 12999, attributes: { color: "Black", size: "9" } },
            { variant_id: 8, sku: "AM270-BLK-10", price: 12999, attributes: { color: "Black", size: "10" } }
        ],
        price: { min: 12999, max: 12999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 6,
        name: "Ultraboost Light",
        brand: "Adidas",
        seller: { seller_id: 6, store_name: "FashionHub" },
        categories: ["Fashion", "Footwear"],
        description: "Adidas performance running shoe",
        tags: ["adidas", "running", "shoes", "sports", "boost"],
        status: "ACTIVE",
        specifications: {
            upper: "Primeknit",
            midsole: "Light BOOST",
            closure: "Lace-up",
            usage: ["Running"],
            gender: "Men",
            drop_mm: 10
        },
        variants: [
            { variant_id: 9, sku: "UB-LIGHT-BLU-9", price: 15999, attributes: { color: "Blue", size: "9" } }
        ],
        price: { min: 15999, max: 15999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    },
    {
        product_id: 7,
        name: "KALLAX Shelf",
        brand: "IKEA",
        seller: { seller_id: 7, store_name: "HomeEssentials" },
        categories: ["Home"],
        description: "Modular storage shelf",
        tags: ["ikea", "shelf", "storage", "furniture", "home", "organiser"],
        status: "ACTIVE",
        specifications: {
            dimensions_cm: { width: 77, height: 147, depth: 39 },
            material: "Engineered Wood",
            compartments: 8,
            max_load_per_shelf_kg: 13,
            assembly_required: true
        },
        variants: [
            { variant_id: 10, sku: "KALLAX-WHT", price: 6999, attributes: { color: "White", material: "Engineered Wood" } }
        ],
        price: { min: 6999, max: 6999 },
        rating: { average: 0, count: 0 },
        updated_at: new Date()
    }
].map(p => ({ ...p, product_id: NumberInt(p.product_id), seller: { ...p.seller, seller_id: NumberInt(p.seller.seller_id) },
              variants: p.variants.map(v => ({ ...v, variant_id: NumberInt(v.variant_id), price: Double(v.price) })),
              price: { min: Double(p.price.min), max: Double(p.price.max) },
              rating: { average: Double(0), count: NumberInt(0) } })));

// Reviews: review_id / user_id / product_id / rating match MySQL `review`.
db.product_reviews.insertMany([
    {
        review_id: 1, product_id: 1, user: { user_id: 1, name: "Aarav Mehta" }, rating: 5,
        title: "Fast and reliable",
        body: "Excellent phone and very good performance.",
        pros: ["Smooth performance", "Great camera"], cons: ["Charger not included"],
        images: ["https://example.com/reviews/r1-1.jpg"],
        verified_purchase: true, order_id: 5,
        helpful: { count: 2, voters: [2, 3] },
        created_at: new Date("2026-08-15T20:00:00Z")
    },
    {
        review_id: 2, product_id: 5, user: { user_id: 2, name: "Diya Sharma" }, rating: 4,
        title: "Comfortable all day",
        body: "Comfortable shoes and good build quality.",
        pros: ["Cushioning", "Looks great"], cons: ["Runs slightly narrow"],
        images: [],
        verified_purchase: true, order_id: 8,
        helpful: { count: 1, voters: [11] },
        seller_reply: { text: "Thanks Diya! Try half a size up for a wider fit.", replied_at: new Date("2026-09-01T10:00:00Z") },
        created_at: new Date("2026-08-31T18:30:00Z")
    },
    {
        review_id: 3, product_id: 3, user: { user_id: 11, name: "Kavya Reddy" }, rating: 5,
        title: "Best productivity mouse",
        body: "Excellent mouse for productivity.",
        pros: ["Quiet clicks", "Multi-device switching", "Long battery"], cons: [],
        images: [],
        verified_purchase: true, order_id: 6,
        helpful: { count: 3, voters: [1, 3, 12] },
        created_at: new Date("2026-08-27T21:00:00Z")
    },
    {
        review_id: 4, product_id: 7, user: { user_id: 3, name: "Rohan Patel" }, rating: 4,
        title: "Good value storage",
        body: "Good storage solution for the price.",
        pros: ["Sturdy", "Easy to assemble"], cons: ["One unit arrived damaged"],
        images: ["https://example.com/reviews/r4-1.jpg", "https://example.com/reviews/r4-2.jpg"],
        verified_purchase: true, order_id: 9,
        helpful: { count: 0, voters: [] },
        created_at: new Date("2026-09-02T19:00:00Z")
    },
    {
        review_id: 5, product_id: 2, user: { user_id: 12, name: "Arjun Nair" }, rating: 3,
        title: "Great screen, unlucky unit",
        body: "Bright display, but my unit had a few dead pixels.",
        pros: ["Bright display", "Battery life"], cons: ["Dead pixels on my unit"],
        images: ["https://example.com/reviews/r5-1.jpg"],
        verified_purchase: true, order_id: 7,
        helpful: { count: 2, voters: [1, 2] },
        seller_reply: { text: "Sorry about that, Arjun. Your replacement request has been approved.", replied_at: new Date("2026-08-30T12:00:00Z") },
        created_at: new Date("2026-08-28T10:30:00Z")
    },
    {
        review_id: 6, product_id: 6, user: { user_id: 11, name: "Kavya Reddy" }, rating: 3,
        title: "Light but sizing is small",
        body: "Light and comfortable, but the sizing runs small.",
        pros: ["Very light", "Responsive cushioning"], cons: ["Sizing runs small"],
        images: [],
        verified_purchase: true, order_id: 6,
        helpful: { count: 1, voters: [2] },
        created_at: new Date("2026-08-26T22:15:00Z")
    }
].map(r => ({ ...r, review_id: NumberInt(r.review_id), product_id: NumberInt(r.product_id), rating: NumberInt(r.rating),
              order_id: NumberInt(r.order_id), user: { ...r.user, user_id: NumberInt(r.user.user_id) },
              helpful: { count: NumberInt(r.helpful.count), voters: r.helpful.voters.map(v => NumberInt(v)) } })));

// View history: [user_id, [[product_id, hours_ago, source], ...]] — times are
// relative to "now" so the 90-day TTL never removes the demo data.
const seedViews = [
    [1,  [[1, 72, "search"], [4, 48, "home"], [3, 30, "recommendation"], [2, 5, "search"]]],
    [2,  [[5, 60, "category"], [6, 40, "recommendation"], [7, 10, "home"]]],
    [3,  [[7, 50, "search"], [3, 20, "home"], [1, 2, "search"]]],
    [4,  [[4, 90, "search"], [3, 26, "recommendation"], [7, 8, "category"]]],
    [11, [[6, 80, "category"], [5, 44, "recommendation"], [3, 12, "search"]]],
    [12, [[2, 70, "search"], [1, 36, "search"], [4, 3, "home"]]]
];

seedViews.forEach(([userId, views]) => {
    db.product_view_events.insertMany(views.map(([productId, h, source]) => ({
        user_id: NumberInt(userId), product_id: NumberInt(productId), viewed_at: hoursAgo(h), source: source
    })));
    db.user_recently_viewed.insertOne({
        user_id: NumberInt(userId),
        items: views
            .map(([productId, h]) => ({ product_id: NumberInt(productId), viewed_at: hoursAgo(h) }))
            .sort((a, b) => b.viewed_at - a.viewed_at)      // newest first
    });
});

print("Seeded: " +
      db.product_catalog.countDocuments() + " products, " +
      db.product_reviews.countDocuments() + " reviews, " +
      db.product_view_events.countDocuments() + " view events, " +
      db.user_recently_viewed.countDocuments() + " recently-viewed lists");


// =====================================================================
// FEATURE 1 — PRODUCT FEATURES / SPECIFICATIONS
// =====================================================================

// 1.1 Product detail page: one read returns everything (no joins)
show("1.1 Product detail — iPhone 16",
    db.product_catalog.find({ product_id: 1 }, { _id: 0 }));

// 1.2 Query inside the flexible specifications
show("1.2 Devices with at least 12 GB RAM",
    db.product_catalog.find(
        { "specifications.ram_gb": { $gte: 12 } },
        { _id: 0, product_id: 1, name: 1, "specifications.ram_gb": 1 }));

show("1.3 Products that have a display spec (phones and laptops only)",
    db.product_catalog.find(
        { "specifications.display": { $exists: true } },
        { _id: 0, name: 1, "specifications.display": 1 }));

show("1.4 Running shoes (array spec contains 'Running')",
    db.product_catalog.find(
        { "specifications.usage": "Running" },
        { _id: 0, name: 1, "specifications.usage": 1 }));

// 1.5 Seller adds a new spec field — no ALTER TABLE needed
db.product_catalog.updateOne(
    { product_id: 3 },
    { $set: { "specifications.scroll_wheel": "MagSpeed electromagnetic", updated_at: new Date() } });

// 1.6 Seller adds a new variant; price range kept consistent in the same update
db.product_catalog.updateOne(
    { product_id: 6 },
    [
        { $set: { variants: { $concatArrays: ["$variants", [{
            variant_id: NumberInt(11), sku: "UB-LIGHT-BLU-10", price: Double(15999),
            attributes: { color: "Blue", size: "10" } }]] } } },
        { $set: { "price.min": { $min: "$variants.price" },
                  "price.max": { $max: "$variants.price" },
                  updated_at: "$$NOW" } }
    ]);

show("1.6 Ultraboost after adding size 10",
    db.product_catalog.find({ product_id: 6 }, { _id: 0, name: 1, variants: 1, price: 1 }));

// 1.7 Spec comparison: two phones side by side
show("1.7 Compare iPhone 16 vs Galaxy S25",
    db.product_catalog.aggregate([
        { $match: { product_id: { $in: [1, 2] } } },
        { $project: { _id: 0, name: 1, "price.min": 1,
                      processor: "$specifications.processor",
                      ram_gb: "$specifications.ram_gb",
                      camera_mp: "$specifications.rear_camera_mp",
                      battery_mah: "$specifications.battery_mah",
                      refresh_hz: "$specifications.display.refresh_hz" } }
    ]));

// 1.8 Validation: these inserts are rejected by the validator
try {
    db.product_catalog.insertOne({ product_id: NumberInt(99), name: "Broken product" });
} catch (e) { print("\n1.8a Rejected (missing required fields): " + e.message); }

try {
    db.product_catalog.insertOne({
        product_id: NumberInt(98), name: "Bad price", brand: "Test",
        seller: { seller_id: NumberInt(5), store_name: "TechWorld" },
        categories: ["Electronics"], status: "ACTIVE", specifications: {},
        variants: [{ variant_id: NumberInt(98), sku: "BAD", price: Double(100) }],
        price: { min: Double(500), max: Double(100) }
    });
} catch (e) { print("1.8b Rejected (price.min > price.max): " + e.message); }


// =====================================================================
// FEATURE 2 — PRODUCT REVIEWS
// =====================================================================

// 2.1 Keep the rating summary on each product up to date ($merge writes
// the aggregation result back into product_catalog)
function refreshRatings() {
    db.product_reviews.aggregate([
        { $group: { _id: "$product_id",
                    average: { $avg: "$rating" },
                    count: { $sum: 1 } } },
        { $set: { product_id: "$_id",
                  rating: { average: { $round: ["$average", 2] },
                            count: { $toInt: "$count" } } } },
        { $unset: ["_id", "average", "count"] },
        { $merge: { into: "product_catalog", on: "product_id",
                    whenMatched: "merge", whenNotMatched: "discard" } }
    ]);
}
refreshRatings();

show("2.1 Rating summary per product (written back by $merge)",
    db.product_catalog.find({}, { _id: 0, product_id: 1, name: 1, rating: 1 }).sort({ product_id: 1 }));

// 2.2 Reviews for a product, most helpful first, with pagination
show("2.2 Galaxy S25 reviews (most helpful first, page 1)",
    db.product_reviews.find(
        { product_id: 2 },
        { _id: 0, "user.name": 1, rating: 1, title: 1, body: 1, cons: 1, "helpful.count": 1, seller_reply: 1 })
        .sort({ "helpful.count": -1, created_at: -1 }).skip(0).limit(5));

// 2.3 Star distribution (the "5★ 60% / 4★ 20%..." bar on a product page)
show("2.3 Star distribution across the marketplace",
    db.product_reviews.aggregate([
        { $group: { _id: "$rating", reviews: { $sum: 1 } } },
        { $sort: { _id: -1 } },
        { $project: { _id: 0, stars: "$_id", reviews: 1 } }
    ]));

// 2.4 Mark a review helpful — one vote per user (the $ne guard makes it idempotent)
function markHelpful(reviewId, voterId) {
    return db.product_reviews.updateOne(
        { review_id: reviewId, "helpful.voters": { $ne: voterId } },
        { $addToSet: { "helpful.voters": NumberInt(voterId) }, $inc: { "helpful.count": 1 } });
}
print("\n2.4 First vote modified: " + markHelpful(4, 12).modifiedCount +
      ", duplicate vote modified: " + markHelpful(4, 12).modifiedCount);

// 2.5 Seller replies to a review
db.product_reviews.updateOne(
    { review_id: 6 },
    { $set: { seller_reply: { text: "Thanks Kavya — we've added a sizing note to the listing.",
                              replied_at: new Date() } } });

// 2.6 Most common complaints per product (unwind the cons array)
show("2.6 Complaints by product",
    db.product_reviews.aggregate([
        { $unwind: "$cons" },
        { $group: { _id: "$product_id", complaints: { $push: "$cons" } } },
        { $lookup: { from: "product_catalog", localField: "_id", foreignField: "product_id", as: "product" } },
        { $project: { _id: 0, product: { $first: "$product.name" }, complaints: 1 } },
        { $sort: { product: 1 } }
    ]));

// 2.7 Average rating per seller, joining reviews to the catalog
show("2.7 Average rating per seller",
    db.product_reviews.aggregate([
        { $lookup: { from: "product_catalog", localField: "product_id", foreignField: "product_id", as: "p" } },
        { $unwind: "$p" },
        { $group: { _id: "$p.seller.store_name",
                    avg_rating: { $avg: "$rating" },
                    reviews: { $sum: 1 } } },
        { $project: { _id: 0, store: "$_id", avg_rating: { $round: ["$avg_rating", 2] }, reviews: 1 } },
        { $sort: { avg_rating: -1 } }
    ]));

// 2.8 Validation: rating out of range and a duplicate review are both rejected
try {
    db.product_reviews.insertOne({
        review_id: NumberInt(50), product_id: NumberInt(4), user: { user_id: NumberInt(4), name: "Neha Iyer" },
        rating: NumberInt(7), body: "Too good to be true!", created_at: new Date() });
} catch (e) { print("\n2.8a Rejected (rating 7): " + e.message); }

try {
    db.product_reviews.insertOne({
        review_id: NumberInt(51), product_id: NumberInt(1), user: { user_id: NumberInt(1), name: "Aarav Mehta" },
        rating: NumberInt(4), body: "Second review for the same phone.", created_at: new Date() });
} catch (e) { print("2.8b Rejected (same user, same product): " + e.message); }


// =====================================================================
// FEATURE 3 — PRODUCT SEARCH / FILTERING
// =====================================================================

// 3.1 Keyword search ranked by relevance (text index with field weights)
show("3.1 Search: 'running shoes'",
    db.product_catalog.find(
        { $text: { $search: "running shoes" } },
        { _id: 0, name: 1, brand: 1, "price.min": 1, score: { $meta: "textScore" } })
        .sort({ score: { $meta: "textScore" } }));

show("3.2 Search: phrase \"apple laptop\" excluding phones",
    db.product_catalog.find(
        { $text: { $search: "\"apple\" laptop -smartphone" } },
        { _id: 0, name: 1, score: { $meta: "textScore" } })
        .sort({ score: { $meta: "textScore" } }));

// 3.3 Pure filtering: category + price range + minimum rating, sorted by price
show("3.3 Smartphones between ₹60,000 and ₹80,000 rated 3+",
    db.product_catalog.find(
        { categories: "Smartphones",
          "price.min": { $gte: 60000, $lte: 80000 },
          "rating.average": { $gte: 3 },
          status: "ACTIVE" },
        { _id: 0, name: 1, "price.min": 1, "rating.average": 1 })
        .sort({ "price.min": 1 }));

// 3.4 Variant-level filter: a specific size AND under a price, in the SAME variant
show("3.4 Footwear with size 9 under ₹15,000 ($elemMatch)",
    db.product_catalog.find(
        { categories: "Footwear",
          variants: { $elemMatch: { "attributes.size": "9", price: { $lt: 15000 } } } },
        // $elemMatch in the projection returns exactly the matching variant.
        // (The positional "variants.$" is unreliable here because the query also
        //  matches another array, `categories`, so $ would point at the wrong index.)
        { _id: 0, name: 1,
          variants: { $elemMatch: { "attributes.size": "9", price: { $lt: 15000 } } } }));

// 3.5 Autocomplete on product name (prefix match)
show("3.5 Autocomplete: 'ma'",
    db.product_catalog.find(
        { name: { $regex: "^ma", $options: "i" } },
        { _id: 0, name: 1 }).limit(5));

// 3.6 Faceted search: one query returns results AND the sidebar filter counts
show("3.6 Faceted search on category 'Electronics'",
    db.product_catalog.aggregate([
        { $match: { categories: "Electronics", status: "ACTIVE" } },
        { $facet: {
            results: [
                { $sort: { "rating.average": -1, "price.min": 1 } },
                { $project: { _id: 0, name: 1, brand: 1, "price.min": 1, "rating.average": 1 } }
            ],
            brands: [
                { $group: { _id: "$brand", count: { $sum: 1 } } },
                { $sort: { count: -1, _id: 1 } }
            ],
            price_ranges: [
                { $bucket: { groupBy: "$price.min",
                             boundaries: [0, 10000, 50000, 100000, 1000000],
                             default: "other",
                             output: { count: { $sum: 1 } } } }
            ],
            ram_options: [
                { $match: { "specifications.ram_gb": { $exists: true } } },
                { $group: { _id: "$specifications.ram_gb", count: { $sum: 1 } } },
                { $sort: { _id: 1 } }
            ]
        } }
    ]));

// 3.7 Reusable search function — the shape the Next.js API route will call
function searchProducts({ q, category, brand, minPrice, maxPrice, minRating, sort = "relevance", page = 1, pageSize = 5 } = {}) {
    const filter = { status: "ACTIVE" };
    if (q)         filter.$text = { $search: q };
    if (category)  filter.categories = category;
    if (brand)     filter.brand = brand;
    if (minPrice != null || maxPrice != null) {
        filter["price.min"] = {};
        if (minPrice != null) filter["price.min"].$gte = minPrice;
        if (maxPrice != null) filter["price.min"].$lte = maxPrice;
    }
    if (minRating != null) filter["rating.average"] = { $gte: minRating };

    const projection = { _id: 0, product_id: 1, name: 1, brand: 1, "price.min": 1, "rating.average": 1 };
    let sortSpec;
    if (sort === "relevance" && q) { projection.score = { $meta: "textScore" }; sortSpec = { score: { $meta: "textScore" } }; }
    else if (sort === "price_asc")  sortSpec = { "price.min": 1 };
    else if (sort === "price_desc") sortSpec = { "price.min": -1 };
    else                            sortSpec = { "rating.average": -1 };

    return db.product_catalog.find(filter, projection)
        .sort(sortSpec).skip((page - 1) * pageSize).limit(pageSize).toArray();
}

show("3.7a searchProducts({ q: 'apple' })", searchProducts({ q: "apple" }));
show("3.7b searchProducts({ category: 'Electronics', maxPrice: 80000, sort: 'price_desc' })",
     searchProducts({ category: "Electronics", maxPrice: 80000, sort: "price_desc" }));

// 3.8 Show that the filter uses an index (not a full collection scan)
const plan = db.product_catalog.find({ categories: "Smartphones", "price.min": { $lte: 80000 } })
    .explain("queryPlanner").queryPlanner.winningPlan;
print("\n3.8 Winning plan for category + price filter: " + JSON.stringify(plan).match(/IXSCAN|COLLSCAN/)[0]);


// =====================================================================
// FEATURE 4 — RECENTLY VIEWED AND RECOMMENDATIONS
// =====================================================================

// 4.1 Record a view: log the event, then move the product to the front of
// the user's list, keeping only the 10 most recent (deduplicated)
function recordView(userId, productId, source = "direct") {
    const now = new Date();
    db.product_view_events.insertOne({
        user_id: NumberInt(userId), product_id: NumberInt(productId), viewed_at: now, source: source });

    db.user_recently_viewed.updateOne(                     // create the list for a first-time viewer
        { user_id: NumberInt(userId) },
        { $setOnInsert: { items: [] } },
        { upsert: true });

    db.user_recently_viewed.updateOne(                     // remove an older entry for the same product
        { user_id: userId },
        { $pull: { items: { product_id: productId } } });

    db.user_recently_viewed.updateOne(                     // push to front, cap at 10
        { user_id: userId },
        { $push: { items: { $each: [{ product_id: NumberInt(productId), viewed_at: now }],
                            $position: 0, $slice: 10 } } });
}

recordView(1, 3, "search");   // Aarav looks at the mouse again -> moves to the top
recordView(4, 5, "home");     // Neha looks at Air Max 270
recordView(3, 6, "search");   // Rohan views Ultraboost

// 4.2 "Recently viewed" strip with product names (array order preserved)
show("4.2 Aarav's recently viewed",
    db.user_recently_viewed.aggregate([
        { $match: { user_id: 1 } },
        { $unwind: { path: "$items", includeArrayIndex: "position" } },
        { $lookup: { from: "product_catalog", localField: "items.product_id", foreignField: "product_id", as: "p" } },
        { $project: { _id: 0, position: 1, product_id: "$items.product_id", name: { $first: "$p.name" },
                      price: { $first: "$p.price.min" }, viewed_at: "$items.viewed_at" } },
        { $sort: { position: 1 } }
    ]));

// 4.3 "Similar products" (content-based): score other products by shared
// categories, shared tags and same brand
function similarProducts(productId, limit = 3) {
    const base = db.product_catalog.findOne({ product_id: productId });
    return db.product_catalog.aggregate([
        { $match: { product_id: { $ne: productId }, status: "ACTIVE" } },
        { $addFields: {
            shared_categories: { $setIntersection: ["$categories", base.categories] },
            shared_tags:       { $setIntersection: ["$tags", base.tags] } } },
        { $addFields: {
            similarity: { $add: [
                { $multiply: [{ $size: "$shared_categories" }, 2] },
                { $size: "$shared_tags" },
                { $cond: [{ $eq: ["$brand", base.brand] }, 1, 0] } ] } } },
        { $match: { similarity: { $gt: 0 } } },
        { $sort: { similarity: -1, "rating.average": -1 } },
        { $limit: limit },
        { $project: { _id: 0, name: 1, similarity: 1, shared_tags: 1, "price.min": 1 } }
    ]).toArray();
}
show("4.3 Similar to iPhone 16", similarProducts(1));
show("4.3 Similar to Air Max 270", similarProducts(5));

// 4.4 "Customers who viewed this also viewed" (collaborative, from view events)
function alsoViewed(productId, limit = 3) {
    return db.product_view_events.aggregate([
        { $match: { product_id: productId } },
        { $group: { _id: null, viewers: { $addToSet: "$user_id" } } },
        { $lookup: { from: "product_view_events",
                     let: { viewers: "$viewers" },
                     pipeline: [
                         { $match: { $expr: { $and: [
                             { $in: ["$user_id", "$$viewers"] },
                             { $ne: ["$product_id", productId] } ] } } },
                         { $group: { _id: "$product_id", users: { $addToSet: "$user_id" } } }
                     ],
                     as: "co" } },
        { $unwind: "$co" },
        { $project: { _id: 0, product_id: "$co._id", shared_viewers: { $size: "$co.users" } } },
        { $lookup: { from: "product_catalog", localField: "product_id", foreignField: "product_id", as: "p" } },
        { $project: { product_id: 1, shared_viewers: 1, name: { $first: "$p.name" } } },
        { $sort: { shared_viewers: -1, product_id: 1 } },
        { $limit: limit }
    ]).toArray();
}
show("4.4 Viewers of MX Master 3S also viewed", alsoViewed(3));

// 4.5 Trending: most viewed products in the last 7 days
function trending(limit = 5, exclude = []) {
    return db.product_view_events.aggregate([
        { $match: { viewed_at: { $gte: hoursAgo(24 * 7) } } },
        { $group: { _id: "$product_id", views: { $sum: 1 }, unique_viewers: { $addToSet: "$user_id" } } },
        { $lookup: { from: "product_catalog", localField: "_id", foreignField: "product_id", as: "p" } },
        { $project: { _id: 0, product_id: "$_id", name: { $first: "$p.name" }, views: 1,
                      unique_viewers: { $size: "$unique_viewers" } } },
        { $match: { product_id: { $nin: exclude } } },
        { $sort: { views: -1, name: 1 } },
        { $limit: limit }
    ]).toArray();
}
show("4.5 Trending this week", trending());

// 4.6 Personalised "Recommended for you".
// Profile = categories and tags of the user's recently viewed products.
// Only products the user has NOT viewed and that share at least one
// category or tag qualify; rating is a small tie-breaker. If nothing
// qualifies (new user, or everything relevant already seen), fall back
// to trending.
function recommendForUser(userId, limit = 3) {
    const profile = db.user_recently_viewed.aggregate([
        { $match: { user_id: userId } },
        { $lookup: { from: "product_catalog", localField: "items.product_id", foreignField: "product_id", as: "viewed" } },
        { $project: { _id: 0,
                      viewed_ids: "$items.product_id",
                      categories: { $reduce: { input: "$viewed.categories", initialValue: [],
                                               in: { $setUnion: ["$$value", "$$this"] } } },
                      tags:       { $reduce: { input: "$viewed.tags", initialValue: [],
                                               in: { $setUnion: ["$$value", "$$this"] } } } } }
    ]).toArray()[0];

    const recs = !profile ? [] : db.product_catalog.aggregate([
        { $match: { product_id: { $nin: profile.viewed_ids }, status: "ACTIVE" } },
        { $addFields: { relevance: { $add: [
            { $multiply: [{ $size: { $setIntersection: ["$categories", profile.categories] } }, 2] },
            { $size: { $setIntersection: ["$tags", profile.tags] } } ] } } },
        { $match: { relevance: { $gt: 0 } } },
        { $addFields: { score: { $add: ["$relevance", { $multiply: [{ $ifNull: ["$rating.average", 0] }, 0.2] }] } } },
        { $sort: { score: -1 } },
        { $limit: limit },
        { $project: { _id: 0, name: 1, relevance: 1, score: { $round: ["$score", 2] }, "price.min": 1 } }
    ]).toArray();

    return recs.length > 0 ? recs : trending(limit, profile ? profile.viewed_ids : []).map(t => ({ ...t, reason: "trending (fallback)" }));
}
show("4.6 Recommended for Rohan (viewed shelf, mouse, iPhone, Ultraboost)", recommendForUser(3));
show("4.6 Recommended for Arjun (viewed phones and a laptop)", recommendForUser(12));
show("4.6 Recommended for Diya (has already seen every fashion/home item)", recommendForUser(2));
show("4.6 Recommended for a brand-new user (no history)", recommendForUser(999));

// 4.7 Where do views come from? (views per traffic source)
show("4.7 Views by source",
    db.product_view_events.aggregate([
        { $group: { _id: "$source", views: { $sum: 1 } } },
        { $sort: { views: -1 } },
        { $project: { _id: 0, source: "$_id", views: 1 } }
    ]));

// =====================================================================
// FEATURE 5 — VECTOR SEARCH (SEMANTIC SEARCH)
// =====================================================================
// Keyword search ($text, section 3) only finds products that share WORDS
// with the query. Vector search finds products with the same MEANING:
// "jogging trainers" finds running shoes although neither word appears in
// any product.
//
// How it works:
//   1. An embedding model turns text into a vector of 384 numbers; texts
//      with similar meaning get vectors that point in similar directions.
//      Model: all-MiniLM-L6-v2 (sentence-transformers), mean pooling,
//      vectors normalised to length 1.
//   2. Each product stores the embedding of "name, brand, description,
//      categories, tags" in the field `embedding`.
//   3. A query is embedded with the same model and products are ranked by
//      cosine similarity = A·B / (|A||B|). Because all vectors have length
//      1, cosine similarity is just the dot product A·B (range -1 to 1).
//   4. This is EXACT k-nearest-neighbour search (every product is scored).
//      That is fine for a catalogue of this size; dedicated vector databases
//      and MongoDB Atlas use approximate indexes (HNSW) to search millions
//      of vectors quickly.
//
// mongosh cannot run the embedding model, so the vectors below were
// generated once with the model and pasted in. In the application (next
// phase) the API embeds the user's query at request time with the same
// model and calls the same pipeline.

const PRODUCT_EMBEDDINGS = {
    1: [0.0174, 0.0701, 0.0848, -0.0948, 0.0403, -0.0886, 0.0324, 0.0765, 0.0014, 0.0468, 0.1134, -0.0137, 0.0479, 0.0879, 0.0175, 0.0179, 0.0335, -0.0178, -0.0469, -0.0116, -0.0539, 0.0329, 0.0324, 0.0142, 0.0626, 0.002, -0.0607, -0.0266, -0.0684, -0.0306, -0.0069, 0.0853, 0.0458, 0.071, -0.0047, -0.1164, -0.0222, -0.0176, 0.0377, 0.0165, 0.0334, 0.0553, -0.0122, 0.0524, 0.0273, 0.0523, 0.014, -0.0376, -0.054, -0.0263, 0.0088, 0.0495, -0.0342, 0.0975, -0.0164, -0.0399, -0.0574, -0.0666, 0.0841, 0.0693, 0.0, 0.0019, 0.0135, 0.0976, -0.0476, 0.0402, -0.0098, 0.0055, -0.0338, 0.0246, 0.0604, -0.0111, 0.0853, -0.03, 0.0407, -0.004, 0.0014, 0.0233, -0.0399, -0.0642, -0.0043, -0.0437, -0.054, -0.0768, 0.0123, -0.0491, -0.0367, -0.0092, -0.0649, -0.0463, -0.0794, 0.0167, -0.0353, -0.0207, 0.0031, -0.0152, 0.0068, -0.1115, -0.0298, 0.0107, 0.0134, 0.0173, -0.0298, 0.025, -0.0061, -0.0605, -0.0298, -0.0024, 0.0382, 0.0337, 0.0486, -0.0227, -0.082, -0.0696, 0.0394, -0.0563, 0.0008, 0.081, 0.0429, 0.0406, -0.0731, -0.0107, -0.0237, -0.1012, -0.0464, -0.0138, -0.0329, -0.0, 0.0043, 0.0434, 0.0232, -0.007, -0.0269, -0.0135, 0.0167, 0.07, -0.0253, -0.0046, -0.018, -0.0804, -0.0488, 0.0014, 0.0899, -0.0202, -0.0354, -0.0784, 0.0313, 0.0011, -0.0283, -0.0261, -0.0121, 0.0383, 0.0192, 0.0164, 0.003, -0.016, 0.0486, -0.0212, -0.0498, 0.1112, 0.0153, -0.0798, -0.0227, 0.0405, 0.0684, -0.0756, 0.05, -0.0574, -0.0269, -0.0286, -0.0828, 0.0062, 0.0996, 0.0429, -0.1042, 0.0057, 0.0251, 0.0454, -0.0417, -0.0345, 0.0082, -0.1148, -0.0649, -0.0141, -0.0534, -0.0418, -0.0389, 0.0023, -0.024, 0.0069, -0.0325, -0.0382, 0.0113, 0.0443, 0.0917, -0.0127, -0.0624, 0.0809, 0.0074, 0.0276, 0.0042, 0.0081, 0.0686, 0.1137, -0.0332, -0.0828, -0.0208, 0.0713, -0.0632, 0.0114, -0.0219, 0.07, 0.0225, -0.0452, -0.0084, -0.0885, 0.0963, 0.1202, -0.0398, 0.0032, -0.0255, 0.0288, -0.0433, 0.0, 0.0346, -0.0306, -0.0697, -0.0228, 0.0455, -0.1258, -0.0152, 0.0636, -0.0031, -0.0082, 0.0153, -0.0358, -0.0582, 0.0358, -0.0132, 0.0141, -0.0772, -0.0572, 0.0247, 0.0665, -0.0374, -0.0109, 0.0449, 0.0844, 0.0198, -0.0175, 0.0232, 0.0361, 0.0429, -0.0978, 0.0232, -0.1581, 0.0428, -0.0012, 0.013, 0.0251, -0.0007, -0.05, 0.0461, -0.0175, 0.0392, 0.0617, 0.0626, 0.0243, -0.0084, -0.0809, -0.0156, 0.0636, -0.0203, 0.0003, 0.0809, 0.0152, -0.0782, -0.0297, -0.0584, 0.0149, 0.0456, -0.0482, 0.02, -0.0318, 0.0632, -0.0596, 0.0053, -0.0227, -0.0974, -0.0596, -0.0408, -0.0339, -0.0728, 0.0513, -0.0168, -0.0264, -0.061, 0.0183, 0.0334, 0.0197, -0.0231, 0.0358, 0.0019, -0.0704, 0.1522, 0.108, 0.0265, 0.0655, 0.0481, 0.0273, 0.0516, -0.0497, 0.0183, 0.0284, -0.0204, -0.0257, -0.0397, 0.0132, -0.1223, -0.0, 0.0419, 0.0341, -0.0145, -0.0289, 0.0029, -0.026, 0.0428, -0.0365, 0.1595, -0.031, 0.0864, -0.0841, -0.0841, 0.0453, 0.0969, 0.0116, -0.0434, -0.0123, 0.0453, 0.0142, -0.0519, 0.0621, -0.0867, -0.0344, 0.085, 0.0031, -0.0224, -0.0689, 0.0242, -0.0135, 0.059, -0.0044, -0.0066, -0.0106, 0.002, -0.0262, -0.0118, -0.0744, 0.058, -0.0429, -0.0278, -0.0362, -0.0305, -0.0117, -0.0063, -0.0736, 0.0629, -0.0655, -0.0027, 0.0527, -0.0559, -0.0727, 0.063, 0.002, 0.0483, -0.0496, 0.0504, -0.0685, -0.0143, -0.0526, 0.111, 0.0135, 0.0219, 0.0925],
    2: [-0.0539, 0.0346, 0.0015, -0.0491, 0.0455, -0.0413, 0.0431, 0.041, -0.0281, 0.0432, 0.0623, 0.0259, 0.1378, -0.0053, 0.0151, -0.0828, -0.0472, -0.0296, 0.0202, 0.0118, 0.0162, 0.0484, -0.0143, 0.001, 0.0306, -0.0426, -0.1008, 0.0073, -0.0303, -0.0669, 0.0777, 0.1329, -0.0285, 0.0618, -0.0467, -0.1197, -0.0353, 0.0112, 0.0907, -0.038, 0.0129, -0.0123, 0.0053, -0.0178, 0.0438, -0.0222, -0.0468, -0.0665, -0.07, 0.0231, -0.0074, -0.0202, -0.0702, 0.0062, -0.0124, 0.0094, -0.0501, -0.0895, 0.0643, -0.0071, 0.0643, -0.0905, -0.0256, 0.061, -0.0475, 0.0628, 0.0303, -0.0226, 0.0318, 0.0226, 0.0234, -0.0469, 0.0678, 0.0516, -0.0119, -0.0156, 0.0291, 0.0093, -0.0115, -0.0112, -0.041, -0.0399, -0.1364, -0.0374, 0.0298, -0.0873, -0.0167, 0.0263, -0.0395, -0.0256, -0.0623, 0.0039, -0.076, -0.0366, -0.1152, -0.0247, -0.0618, -0.0754, -0.0115, 0.0236, 0.0157, 0.0455, 0.0518, 0.0035, -0.0153, -0.0006, -0.045, 0.0445, 0.0686, -0.05, -0.0297, -0.0189, -0.1183, -0.0108, -0.0257, -0.026, 0.004, 0.0398, 0.0433, 0.0478, -0.0423, 0.0071, -0.0936, -0.1653, -0.0549, -0.0026, -0.0452, -0.0, 0.0186, 0.0358, 0.0227, 0.0575, 0.0253, 0.1065, -0.0361, 0.0493, 0.0029, 0.0148, 0.0059, -0.0286, -0.0382, 0.0559, 0.0616, -0.0294, -0.0415, -0.106, -0.0002, -0.0468, 0.0237, -0.0187, -0.0602, -0.0357, 0.0387, -0.0217, 0.0634, -0.0115, 0.0795, 0.0468, -0.059, 0.0109, 0.0697, -0.0087, 0.0163, 0.02, 0.017, -0.0245, 0.0765, -0.0654, -0.0008, 0.0224, -0.1288, 0.0875, 0.0037, 0.0464, -0.0, 0.045, 0.0042, 0.0299, -0.0785, -0.0962, 0.0236, -0.0704, -0.0358, 0.0307, -0.0556, -0.0338, -0.0803, 0.0277, -0.0211, -0.0215, 0.0055, 0.0086, 0.0856, 0.0385, 0.1204, 0.0163, -0.0535, 0.0541, 0.0122, 0.0425, 0.067, 0.0247, 0.0542, 0.0783, 0.0319, -0.0319, -0.0419, 0.0021, -0.0804, -0.0137, 0.0137, 0.0602, -0.0183, -0.0096, -0.0501, -0.1198, 0.0577, 0.0244, -0.0227, -0.0178, 0.0466, 0.0524, -0.055, -0.0, 0.0217, 0.0319, -0.0271, -0.0292, 0.0432, -0.0447, 0.0227, 0.0823, -0.0535, 0.0143, -0.0006, 0.0144, -0.0918, -0.0231, 0.0047, -0.0075, -0.0153, -0.0872, 0.0206, 0.033, -0.0259, 0.0263, 0.0661, 0.0961, 0.038, 0.0917, 0.0044, 0.0539, 0.0301, -0.0111, 0.0068, -0.0976, 0.086, -0.059, 0.009, 0.0184, 0.0369, 0.0354, 0.0446, -0.0114, -0.0103, 0.0355, 0.0589, 0.0326, 0.054, -0.144, 0.0029, -0.0101, 0.0054, -0.0509, 0.0438, -0.024, -0.0564, -0.0175, -0.0384, -0.0062, 0.0623, -0.0376, -0.0188, -0.0459, 0.0701, -0.0077, -0.0032, -0.0051, -0.092, -0.0688, -0.0105, -0.0186, -0.0024, 0.0214, -0.0268, -0.0086, -0.0565, -0.021, -0.0009, 0.0499, -0.053, 0.0216, -0.0047, -0.071, 0.1591, 0.0247, -0.0494, 0.0465, -0.0019, -0.0499, 0.0092, -0.0059, 0.0103, -0.0026, -0.0831, 0.0317, -0.0581, 0.0373, -0.0473, -0.0, 0.0743, 0.0242, -0.0266, 0.0067, 0.0057, 0.03, -0.025, -0.0382, 0.1666, -0.0278, 0.0216, -0.083, -0.0216, -0.0151, -0.0084, 0.0389, -0.0566, 0.0296, -0.0034, 0.0553, -0.0085, 0.0334, -0.0653, -0.0336, 0.0828, -0.0534, -0.015, -0.0157, 0.0673, -0.0151, 0.0088, -0.0441, -0.0519, 0.0617, 0.0293, -0.0006, 0.0716, -0.125, 0.0719, 0.0232, 0.0132, -0.0185, -0.0344, 0.0168, -0.0346, -0.1036, 0.0922, 0.0066, 0.0014, 0.0504, -0.0928, -0.0624, -0.0672, -0.002, -0.0031, -0.0108, 0.0532, -0.0298, -0.0153, 0.0201, 0.1005, 0.0155, 0.0188, 0.121],
    3: [-0.0474, -0.0738, 0.0387, -0.0603, 0.0952, -0.0717, 0.1075, -0.0039, -0.0405, 0.0313, 0.0685, 0.0554, 0.0144, -0.0269, 0.0483, 0.0532, 0.0015, 0.0455, 0.0627, 0.0327, 0.0398, -0.0242, 0.049, 0.0428, -0.0182, 0.01, 0.0279, -0.0729, -0.0644, -0.0971, -0.0219, 0.0355, 0.0266, 0.0261, -0.0229, -0.1508, 0.037, 0.0036, -0.0435, -0.0339, -0.054, 0.0016, 0.1327, -0.016, 0.0408, 0.0267, -0.0141, -0.0737, -0.0183, 0.0773, 0.0584, -0.1182, 0.0365, 0.0534, -0.005, 0.1073, -0.0077, -0.0418, 0.0178, 0.0359, 0.0004, 0.0597, -0.0424, -0.0248, 0.0585, 0.0312, -0.0294, 0.0416, -0.0172, 0.0277, -0.0512, -0.0601, 0.0018, 0.0292, 0.0104, -0.0027, 0.0428, -0.0199, 0.0762, -0.0134, -0.0873, -0.0181, -0.0234, -0.0267, 0.0517, -0.0091, -0.0301, 0.0608, 0.0026, -0.0157, -0.093, 0.0033, -0.032, 0.0565, -0.0468, -0.0281, 0.0241, -0.011, 0.0036, 0.0435, 0.0343, 0.057, 0.0051, -0.0138, -0.058, -0.0158, -0.0318, 0.0163, -0.0023, -0.0034, 0.01, -0.0221, -0.1069, 0.0129, 0.0501, 0.0117, -0.0018, 0.0265, 0.1793, 0.0706, -0.0241, 0.0067, -0.0857, -0.1164, -0.0434, 0.0053, 0.0045, -0.0, -0.0374, 0.0499, -0.0273, 0.0201, 0.0066, 0.0644, 0.0612, -0.0094, -0.0214, 0.0085, -0.1164, 0.0306, -0.0824, 0.0588, 0.0616, -0.0999, 0.0389, 0.059, -0.0028, -0.0139, -0.0005, 0.0166, -0.0384, -0.0039, 0.062, 0.0518, -0.0642, -0.008, 0.125, 0.062, -0.009, 0.0257, 0.0027, -0.0297, -0.061, 0.008, -0.0339, -0.1248, 0.0171, 0.0164, -0.1006, -0.0486, -0.0849, -0.062, -0.0253, -0.0375, -0.0085, -0.0081, 0.0921, -0.0643, -0.06, -0.065, -0.024, -0.0985, 0.0359, -0.1222, -0.0734, 0.0824, 0.0437, 0.0131, -0.0619, -0.0024, 0.0817, -0.0303, 0.0938, 0.0602, 0.1053, 0.0106, -0.0334, -0.0185, -0.0411, -0.0179, 0.024, -0.0293, 0.019, 0.0289, -0.0608, -0.019, -0.0911, -0.0222, -0.0532, -0.0111, -0.0669, 0.0964, 0.0083, -0.0521, -0.0477, -0.0356, -0.0465, 0.0387, -0.0108, 0.0594, -0.0914, 0.0446, -0.0787, 0.0, -0.0152, 0.0134, -0.0386, 0.0275, -0.0345, 0.022, 0.0255, 0.0089, -0.0298, -0.0093, -0.0136, -0.0494, -0.0813, 0.0042, 0.0369, 0.015, -0.0532, -0.0299, 0.0465, -0.0406, 0.0745, -0.0083, 0.0176, 0.0582, 0.0307, -0.0118, -0.0589, 0.0135, 0.0242, -0.0094, -0.019, 0.0158, 0.0781, 0.0181, 0.1285, -0.0173, 0.0626, 0.0089, 0.0429, -0.0209, 0.0183, 0.0525, 0.0782, 0.0496, 0.0406, -0.0963, -0.0802, 0.0014, 0.1101, 0.0722, -0.0239, -0.1098, -0.0142, -0.1105, -0.0645, -0.0157, -0.0363, -0.0397, -0.0093, -0.0046, 0.0098, -0.0265, 0.0079, 0.0576, 0.0085, 0.007, 0.0682, 0.064, 0.0105, 0.0394, 0.026, 0.102, 0.0886, 0.0123, 0.0066, -0.0182, 0.0415, -0.0006, 0.0175, -0.0873, 0.1049, 0.0195, 0.0744, -0.0088, -0.0415, -0.0326, 0.0223, 0.0756, 0.0083, -0.0575, 0.0273, -0.0345, -0.0772, 0.0247, -0.0338, -0.0, 0.0077, 0.0155, 0.0247, -0.0363, 0.0293, 0.0557, 0.0245, 0.0391, 0.0307, 0.0173, 0.0277, -0.0955, 0.025, 0.0125, 0.1105, 0.0251, 0.0054, 0.0286, -0.0185, -0.0186, 0.0258, 0.039, 0.003, -0.0304, 0.0619, -0.0014, -0.0805, 0.0728, 0.0234, -0.0063, 0.0271, 0.0288, 0.0377, 0.0082, -0.0409, -0.0094, 0.0114, -0.0473, -0.0294, -0.0604, 0.0028, -0.0178, -0.0276, -0.0502, -0.0391, -0.1335, 0.0222, -0.0648, -0.0776, -0.0065, -0.0586, -0.0132, 0.0499, -0.0042, 0.0027, 0.0359, -0.0113, -0.0605, 0.0216, -0.0674, 0.0754, 0.0295, -0.0069, 0.0751],
    4: [0.037, 0.0284, 0.0249, 0.0628, 0.078, -0.0231, 0.0283, 0.0333, 0.0054, 0.0557, 0.1065, 0.0176, 0.0658, -0.0265, 0.0017, 0.0672, 0.0796, -0.0574, 0.0353, 0.0178, 0.0316, 0.0355, -0.0231, 0.0283, 0.0314, -0.0041, 0.0342, 0.0203, -0.0811, -0.0529, -0.0224, 0.0233, -0.001, 0.0623, 0.0382, -0.0506, 0.0832, -0.0159, 0.0199, -0.0956, -0.0653, 0.0152, 0.1089, 0.0657, 0.0164, 0.0463, 0.0156, -0.0712, 0.03, 0.0316, 0.0442, -0.0697, -0.0598, 0.0508, 0.0046, 0.0273, -0.05, -0.1131, 0.0428, 0.017, 0.0496, -0.0627, -0.0069, 0.0635, 0.0173, 0.0245, -0.0178, -0.0246, -0.0548, 0.0107, 0.0591, -0.055, 0.0556, 0.0651, -0.0285, -0.0491, 0.0097, -0.0469, 0.0141, 0.0648, -0.0859, -0.0092, -0.0944, -0.0691, 0.0055, -0.042, -0.0242, -0.0925, -0.082, 0.0167, -0.0209, 0.0179, 0.0116, -0.0013, -0.0395, -0.0641, 0.0382, -0.0206, -0.0046, 0.0411, -0.0362, 0.068, 0.0787, -0.004, -0.0273, -0.0329, 0.0084, 0.0268, 0.0186, 0.0024, -0.0322, -0.0556, -0.1072, -0.0001, 0.0157, -0.0223, 0.0374, -0.0262, -0.0037, 0.0748, -0.0755, 0.0443, 0.0338, -0.1126, -0.0129, 0.014, -0.0698, -0.0, 0.0225, 0.0081, 0.0507, -0.021, -0.0138, -0.0754, 0.0231, -0.0197, 0.0241, 0.0472, -0.0735, 0.0007, -0.0238, 0.0419, 0.1051, -0.0781, -0.0024, -0.0598, 0.0059, 0.0276, -0.0708, 0.0121, 0.024, -0.0591, 0.0008, 0.0049, 0.0147, -0.0123, 0.0875, 0.0557, -0.0874, 0.0132, -0.0597, -0.1619, -0.0997, -0.0346, -0.0502, -0.0663, 0.0444, -0.0376, -0.1321, -0.0085, -0.0642, -0.0747, 0.0639, 0.0297, -0.051, 0.0751, 0.0123, 0.0071, -0.0812, -0.0251, 0.0801, -0.0442, -0.0404, -0.0096, -0.0105, 0.0368, -0.013, 0.0973, -0.0333, 0.0474, 0.0002, 0.0139, 0.0366, 0.0452, 0.1032, -0.0038, -0.0355, 0.0158, -0.0095, -0.0388, 0.0574, -0.0195, 0.0493, -0.0291, -0.0498, -0.0101, -0.0921, -0.0101, -0.0419, 0.0289, 0.0401, 0.0277, -0.061, 0.0237, 0.0188, -0.0238, 0.0408, 0.0352, -0.049, 0.0536, -0.0598, 0.0238, -0.057, -0.0, 0.0621, -0.0203, -0.0484, 0.04, 0.0162, 0.0111, -0.0451, 0.0499, -0.1501, -0.0159, 0.008, -0.0129, -0.0718, -0.0262, 0.0865, 0.019, -0.1069, -0.1115, 0.0518, 0.0307, 0.0226, 0.0115, 0.0378, -0.0361, 0.015, -0.0478, -0.0317, 0.1002, -0.0031, 0.0183, -0.0271, -0.0057, 0.0645, 0.0668, 0.028, -0.0674, -0.0353, 0.0148, 0.0505, 0.0254, 0.0456, 0.0899, 0.0252, 0.0369, 0.0123, -0.0503, -0.0635, -0.0447, 0.0924, -0.1215, 0.0248, -0.0723, -0.0483, -0.0281, 0.0052, -0.0332, -0.0382, -0.007, 0.0188, -0.0159, -0.0427, -0.0705, 0.0686, -0.0045, -0.0053, -0.032, -0.0138, -0.0011, -0.0883, -0.0011, 0.0031, 0.0072, 0.0101, 0.0182, 0.0134, 0.0249, 0.0171, -0.0209, -0.0626, -0.0148, 0.098, 0.0552, -0.0023, 0.0427, -0.0162, 0.0206, -0.0011, -0.0348, -0.0255, 0.0272, 0.0285, 0.0019, -0.0013, -0.0135, -0.1223, -0.0, -0.0054, 0.0048, 0.0699, 0.0309, -0.0471, 0.0178, 0.0399, -0.0336, 0.15, 0.0705, 0.097, -0.1376, -0.0339, 0.0263, 0.0517, 0.042, -0.0884, 0.0773, 0.0089, -0.0262, -0.0391, 0.0409, 0.0071, -0.0021, 0.0831, 0.0209, -0.0331, -0.0314, 0.0375, 0.048, -0.0683, 0.0529, -0.0273, -0.0425, -0.0402, -0.0652, 0.0145, -0.0274, 0.0304, 0.0428, -0.0286, -0.0163, -0.0854, -0.0487, 0.0394, -0.0657, -0.0038, -0.0368, -0.0556, 0.0657, 0.0221, -0.0543, 0.0618, 0.0022, -0.0243, 0.0447, 0.0027, -0.0131, -0.0375, -0.0407, 0.1708, -0.0156, -0.0354, 0.1144],
    5: [-0.0343, -0.0436, -0.0621, 0.0257, 0.0798, -0.0411, 0.0274, 0.0308, -0.0772, -0.004, 0.0091, 0.108, -0.0106, -0.0209, -0.0202, 0.0406, -0.0237, 0.0104, -0.0421, -0.004, -0.0375, 0.0218, 0.0518, 0.0661, -0.0467, 0.0735, -0.0256, 0.0387, -0.0212, -0.0387, 0.0455, -0.0161, 0.0714, 0.0554, 0.0369, -0.0805, 0.0021, -0.0393, -0.0545, -0.0082, -0.0319, -0.077, -0.0034, 0.0707, -0.0068, 0.0124, -0.0526, -0.0434, -0.0352, 0.1572, -0.0373, -0.0458, -0.0007, 0.0089, 0.049, 0.0719, -0.1111, -0.0655, 0.0122, -0.0695, 0.0792, -0.0093, -0.0477, 0.0442, -0.0388, 0.0325, -0.035, 0.0459, -0.0038, 0.0334, 0.0416, 0.0069, 0.0328, 0.0769, 0.032, 0.0457, -0.0054, -0.0447, -0.0219, 0.0365, -0.0062, -0.0725, -0.0281, -0.0885, 0.0566, 0.0001, -0.0519, -0.0101, 0.0509, 0.0466, -0.1535, -0.0106, -0.0073, 0.009, -0.0647, 0.0176, -0.0037, -0.0433, -0.0071, 0.0282, 0.0026, 0.0318, 0.0154, 0.0384, -0.0413, -0.0502, -0.0395, 0.0866, 0.0496, 0.0324, -0.0153, -0.0371, 0.046, -0.0691, 0.0316, 0.0053, -0.0282, 0.0546, 0.0644, 0.1267, -0.0186, -0.0009, 0.0259, -0.0804, -0.0802, 0.0176, -0.0104, -0.0, 0.0333, 0.0475, 0.082, -0.0458, -0.0516, 0.0138, 0.0058, -0.0144, -0.019, 0.0667, -0.0159, 0.0636, -0.0125, 0.0993, 0.079, -0.0168, 0.0052, 0.0159, -0.0512, -0.0016, 0.0268, 0.0618, -0.022, 0.0308, 0.0665, -0.0474, 0.049, 0.0316, 0.0145, 0.053, 0.0603, -0.0737, -0.0661, -0.0286, -0.0772, 0.0152, 0.0051, -0.054, -0.0148, 0.0338, 0.006, 0.006, -0.0064, -0.0473, -0.0369, 0.0999, 0.0028, 0.0261, 0.0388, -0.0483, -0.0879, -0.0254, -0.0277, -0.0167, 0.0234, -0.1149, -0.0408, -0.0033, -0.072, 0.0385, -0.04, -0.018, 0.0379, 0.0346, -0.0578, -0.0385, 0.0724, -0.0103, -0.0132, 0.079, 0.0324, 0.0217, 0.0044, 0.0433, 0.0176, -0.0447, 0.0139, 0.0554, -0.0955, -0.0257, -0.0638, -0.0182, 0.0819, 0.0683, -0.0465, 0.0081, -0.0313, -0.0026, 0.0143, -0.0631, -0.0897, -0.0073, -0.0059, 0.0072, -0.031, 0.0, 0.0368, 0.0348, 0.0427, -0.0161, -0.0045, 0.0199, -0.0176, 0.0435, -0.0083, -0.0136, -0.0128, 0.0035, 0.0152, -0.0012, 0.0325, -0.0886, -0.0354, -0.0665, 0.0851, -0.004, 0.0065, 0.0245, 0.0205, 0.0106, -0.0027, 0.0059, 0.0391, 0.1276, -0.0214, 0.0088, 0.073, 0.0089, 0.0207, 0.0854, -0.0214, -0.0541, -0.0752, -0.0275, 0.032, 0.0057, 0.056, 0.0093, -0.0282, 0.0212, 0.0087, -0.1073, 0.0228, -0.1394, 0.0142, -0.1266, 0.0447, -0.0391, -0.0382, 0.0724, -0.0161, -0.0532, -0.091, 0.0111, -0.0599, -0.0126, 0.1065, 0.0825, 0.0109, 0.0378, -0.0091, -0.0731, -0.0593, -0.0206, -0.1329, -0.0069, -0.1019, -0.0101, -0.0129, 0.1742, -0.0596, -0.0316, 0.021, 0.038, 0.0189, 0.0198, -0.0333, -0.0352, 0.022, 0.0887, 0.1251, 0.0866, -0.0511, 0.0349, 0.0584, 0.0178, 0.0362, 0.035, -0.0429, 0.0272, -0.0519, -0.0, 0.0514, 0.0959, -0.0164, 0.0816, -0.0035, 0.0969, 0.0782, -0.0275, 0.0354, 0.0085, 0.0102, -0.0271, 0.0664, 0.0418, 0.016, -0.0737, -0.0608, -0.0015, -0.0094, 0.0267, -0.0712, 0.0326, -0.0075, -0.0008, 0.006, -0.0378, -0.0225, -0.1056, 0.0332, 0.0355, -0.0724, -0.0311, 0.0156, -0.0622, -0.0429, 0.0697, 0.0441, -0.0261, -0.0947, -0.0378, 0.0057, -0.0544, -0.0337, -0.0439, 0.0057, -0.0844, 0.0429, -0.0113, -0.0658, 0.0479, -0.0449, -0.0235, 0.0514, -0.0204, -0.0066, -0.0548, -0.1008, 0.0644, -0.037, -0.0179, 0.102, -0.0869, -0.0725, 0.0686],
    6: [-0.0281, 0.0072, -0.0819, -0.0065, 0.0945, -0.0225, -0.02, 0.0156, -0.0642, 0.011, -0.0052, 0.0508, -0.0275, -0.0136, 0.0106, 0.063, 0.0388, 0.0363, 0.0183, 0.0149, 0.0721, -0.081, 0.0439, 0.0733, -0.0543, 0.0833, -0.0519, -0.0126, -0.0219, -0.0493, 0.0167, -0.0683, 0.0387, 0.0153, -0.002, -0.0097, 0.0255, -0.0566, -0.0232, 0.0479, 0.0341, -0.108, -0.0591, 0.0188, 0.0266, -0.017, -0.01, -0.0091, -0.1069, -0.0375, 0.0, -0.099, -0.0257, 0.0455, 0.0677, 0.0841, -0.0332, -0.0973, 0.0456, -0.0905, 0.0634, 0.0593, -0.0155, 0.0318, 0.0233, 0.0303, -0.0788, 0.0648, -0.003, 0.0475, 0.022, -0.0212, 0.0615, 0.0634, -0.0248, -0.0378, 0.033, -0.016, -0.0463, -0.0246, 0.0069, -0.0975, -0.0111, -0.0392, 0.0754, -0.0135, -0.0173, -0.0382, -0.0675, -0.0727, -0.0897, -0.0125, 0.0457, 0.052, -0.0373, -0.026, -0.0187, -0.0597, 0.0086, 0.0188, 0.0007, 0.0168, -0.0409, 0.0532, -0.0284, -0.0434, -0.0628, 0.1452, 0.0739, 0.0304, 0.0292, -0.0187, -0.0604, 0.0513, -0.0663, -0.0177, -0.0476, 0.0313, 0.0322, 0.0816, -0.0498, 0.025, 0.0693, -0.0971, -0.0391, -0.027, 0.0159, -0.0, 0.0258, -0.0385, 0.0223, -0.0935, -0.0315, 0.0047, -0.0122, -0.0559, -0.0246, 0.0316, 0.0296, 0.0593, 0.0256, 0.1277, 0.1032, -0.0859, 0.0594, -0.0003, 0.0203, 0.0263, 0.0233, 0.0541, -0.0176, 0.0087, 0.0465, -0.0011, 0.0143, 0.022, -0.0168, 0.0635, 0.0088, -0.0616, -0.0414, -0.0356, -0.0126, 0.0107, 0.0317, -0.0736, 0.0183, -0.0025, -0.0142, -0.0645, -0.0202, -0.0848, -0.0081, 0.1452, -0.0112, 0.0732, -0.0026, 0.02, -0.0432, -0.0549, -0.0442, -0.0214, 0.005, -0.0546, -0.0379, 0.0218, -0.0319, 0.0379, -0.0554, -0.0215, 0.0119, -0.03, -0.0505, -0.0555, 0.0509, 0.0153, -0.0582, 0.0217, -0.0164, 0.0228, 0.0185, 0.0677, 0.0741, -0.0091, 0.0318, 0.0389, -0.0971, 0.0148, -0.0911, -0.0396, 0.0326, -0.0008, -0.0049, 0.0285, -0.0034, -0.0155, -0.0514, 0.0005, -0.0406, 0.0515, -0.042, 0.0067, -0.0735, -0.0, 0.1244, -0.0115, 0.0034, 0.0359, 0.1184, 0.0301, -0.0218, -0.017, -0.02, 0.0157, 0.0109, -0.0455, -0.097, -0.0115, 0.0299, -0.0193, -0.0374, -0.0062, 0.0046, 0.0154, 0.0489, 0.051, 0.0367, -0.0135, -0.006, -0.0316, 0.0941, 0.1115, -0.0906, -0.0106, 0.0418, 0.0065, -0.0496, -0.005, -0.0319, 0.0358, -0.0784, -0.0597, -0.0019, -0.0025, 0.0537, 0.0779, -0.0377, 0.0088, -0.0509, -0.0539, -0.1079, -0.087, -0.0135, -0.0626, 0.0463, -0.0331, 0.0085, 0.1132, -0.0817, -0.0666, -0.0914, 0.0573, -0.0726, 0.0371, 0.0732, 0.0515, 0.0107, 0.0175, 0.0298, -0.1049, -0.0279, -0.1036, -0.0534, 0.0252, 0.0296, -0.0048, -0.0492, 0.2013, -0.0754, -0.0142, -0.0183, 0.0495, 0.0001, -0.0125, 0.0183, -0.0032, 0.0581, 0.071, 0.0384, 0.0788, 0.0088, 0.0129, 0.0021, -0.0593, 0.1002, 0.0569, -0.0267, 0.0493, -0.0226, -0.0, 0.0126, 0.0414, 0.0172, 0.0822, 0.0339, 0.035, 0.0093, -0.0441, 0.0132, -0.0146, 0.0496, -0.071, 0.0384, 0.011, 0.038, -0.0107, 0.01, 0.0276, 0.0008, 0.0278, -0.0866, 0.04, 0.0215, -0.0018, 0.0375, -0.0138, 0.0012, -0.0771, 0.088, 0.0403, 0.0302, 0.0441, 0.1009, -0.0482, 0.0368, 0.0583, -0.0052, -0.0269, -0.0294, 0.0213, -0.0102, -0.0188, 0.0338, -0.0199, -0.0244, -0.1058, -0.0031, 0.0336, -0.055, 0.0245, -0.0165, -0.0641, -0.0369, -0.0051, -0.0141, 0.0078, -0.1, 0.0273, -0.0485, 0.022, 0.1762, -0.083, -0.0098, 0.083],
    7: [-0.0689, -0.0096, -0.0758, 0.0124, -0.0134, -0.0395, -0.024, -0.052, 0.0207, 0.0155, 0.0397, -0.0057, 0.073, 0.0353, 0.0439, -0.0516, -0.0616, 0.0138, -0.0056, 0.0083, -0.01, 0.0026, 0.0501, 0.0216, 0.063, 0.0714, -0.0424, 0.0069, 0.0315, -0.0726, 0.01, -0.013, -0.0148, 0.0197, 0.0402, 0.0247, -0.0304, -0.0184, 0.0175, -0.0567, -0.0163, 0.0599, -0.0258, 0.0446, -0.0777, -0.0027, -0.0246, -0.1332, -0.0107, 0.025, -0.0434, -0.0524, -0.0025, 0.0335, 0.0132, 0.1268, -0.0348, -0.0704, 0.0783, 0.004, 0.0728, -0.0249, 0.055, 0.0328, -0.0511, 0.0757, -0.0345, 0.0908, -0.0501, -0.0047, 0.0471, -0.0011, 0.0595, 0.0806, 0.0905, -0.0759, 0.0305, -0.0845, 0.0124, 0.0289, -0.0643, 0.0408, -0.0471, -0.036, -0.0876, -0.0293, -0.018, -0.0439, -0.0211, -0.0392, 0.0043, 0.0268, 0.0943, -0.0515, -0.1124, 0.0031, 0.0216, 0.027, 0.0657, -0.0105, 0.012, 0.0353, 0.1151, 0.038, -0.1101, -0.0906, -0.0576, 0.0056, -0.0201, -0.0459, -0.1135, -0.0033, -0.1162, -0.0739, -0.044, 0.0203, 0.0513, -0.0041, 0.0408, -0.0261, 0.0127, -0.0454, 0.0295, -0.0228, -0.0015, 0.0224, -0.0239, -0.0, 0.008, 0.0205, 0.0215, 0.0103, 0.0957, -0.0707, -0.0214, 0.0391, -0.0885, 0.0306, 0.0404, 0.0318, -0.1021, 0.029, 0.0964, 0.0352, -0.0193, -0.0012, 0.053, -0.0195, 0.0584, 0.0307, 0.03, 0.0102, -0.0183, -0.0765, 0.0578, -0.014, -0.0094, 0.0337, 0.0358, -0.0249, 0.0167, -0.0591, -0.0895, -0.0168, -0.0747, -0.03, -0.0071, -0.0677, -0.0115, 0.0419, 0.0216, 0.1262, 0.0242, 0.0271, 0.018, -0.0057, 0.0792, 0.021, -0.0677, -0.0118, -0.0578, 0.0579, 0.0143, -0.0057, 0.02, -0.0304, 0.0199, -0.0001, 0.0576, 0.017, 0.06, 0.0245, 0.0534, -0.0464, 0.019, -0.0124, 0.0536, -0.0381, -0.0381, 0.0241, -0.0058, 0.0665, 0.0277, 0.0052, -0.1344, 0.0068, -0.0872, -0.068, 0.0022, -0.0118, 0.0468, 0.1468, -0.0274, -0.0485, 0.0393, -0.0332, -0.0465, 0.0327, -0.0627, -0.0182, -0.0036, 0.0201, -0.0568, -0.0, 0.1058, -0.0694, -0.0614, 0.0368, 0.0809, -0.0028, -0.0101, -0.019, -0.0088, 0.0294, -0.0047, -0.007, 0.0138, 0.0594, 0.0123, 0.0018, 0.0165, -0.0288, 0.0314, 0.0045, -0.0152, -0.0298, -0.0396, 0.0613, -0.0047, 0.0049, 0.021, -0.0087, -0.0302, 0.0369, -0.1457, -0.0635, 0.0536, 0.0326, -0.0095, -0.1057, -0.0434, -0.0635, -0.0216, -0.0495, 0.0415, 0.0579, -0.0168, 0.0295, -0.0134, -0.1312, -0.0363, -0.0004, 0.0751, -0.0474, 0.0114, 0.0116, -0.0638, -0.1128, 0.0532, 0.046, -0.0297, 0.0127, 0.0332, 0.0529, -0.0448, 0.0482, 0.0463, 0.0686, 0.04, -0.0625, 0.002, -0.088, -0.0848, -0.0097, 0.0172, 0.0764, 0.0035, 0.0636, 0.0323, 0.0053, 0.0122, 0.0754, 0.0792, -0.0411, 0.0973, -0.0611, -0.0301, 0.0841, 0.0445, -0.0586, 0.0188, 0.0592, 0.0468, -0.0217, 0.0392, -0.0118, -0.0528, 0.0485, 0.1032, -0.0, 0.0103, 0.0116, -0.0548, -0.0406, -0.0226, -0.0818, 0.0852, 0.0349, 0.0114, -0.0101, 0.0884, 0.0168, -0.0286, 0.0103, -0.0607, 0.0141, -0.02, 0.039, 0.0198, 0.0223, 0.0084, -0.012, 0.0272, -0.0392, 0.0271, 0.0061, -0.0813, -0.0116, 0.0628, -0.0467, 0.0455, -0.0446, -0.0042, -0.0206, 0.0674, 0.0394, -0.0749, -0.0167, -0.0529, -0.042, -0.037, -0.1548, -0.0999, -0.0274, 0.0251, 0.1044, -0.0079, 0.0878, 0.0196, 0.0083, -0.099, -0.0561, 0.0076, -0.048, -0.0333, -0.0084, -0.0041, -0.0071, 0.0738, -0.0136, 0.1173, 0.0026, -0.0683, 0.0763],
};

const QUERY_EMBEDDINGS = {
    "jogging trainers": [0.0148, 0.0252, 0.0017, 0.0568, 0.0337, 0.0198, 0.0046, -0.0153, -0.0093, -0.038, 0.0963, 0.0292, 0.0072, 0.0053, 0.019, 0.0109, 0.0108, 0.0626, -0.0988, -0.0229, -0.0228, -0.0144, 0.041, 0.0667, -0.1112, 0.0499, -0.0225, -0.0386, -0.063, 0.0153, -0.0474, -0.1019, 0.0502, 0.0484, -0.0178, -0.0453, 0.0562, -0.001, -0.0944, 0.0823, -0.0408, -0.1261, -0.006, -0.0172, 0.0272, 0.0098, 0.0154, 0.0367, -0.0671, 0.0592, 0.0287, -0.0518, 0.0512, -0.0158, 0.0437, 0.0095, -0.0752, 0.0704, -0.0073, 0.007, 0.1278, 0.0151, -0.0986, 0.0081, -0.1055, -0.0605, 0.027, 0.0643, 0.0484, -0.0171, 0.0034, -0.0423, -0.0027, 0.0186, -0.0034, 0.0535, -0.0105, -0.0063, -0.0035, -0.021, 0.0073, -0.0662, 0.0008, -0.0066, 0.107, 0.0882, 0.0128, 0.0144, 0.0065, 0.0241, -0.0608, 0.0156, -0.0883, 0.0103, -0.0679, 0.021, -0.0499, 0.0173, -0.0517, 0.1147, 0.0231, -0.0112, 0.1237, 0.0865, -0.0349, -0.0795, -0.067, 0.0275, 0.1141, 0.0893, -0.0102, -0.0392, -0.0004, 0.0431, 0.0172, 0.0221, -0.0431, 0.0922, -0.0426, 0.1434, -0.0544, -0.0295, -0.0124, -0.0087, -0.0388, -0.0562, -0.0691, -0.0, -0.0575, 0.0038, 0.0569, -0.0474, -0.0205, -0.0898, -0.0255, -0.0779, 0.0124, 0.0293, -0.0285, 0.0707, 0.0317, 0.0421, 0.1034, -0.0319, -0.0236, 0.0173, 0.0204, 0.0388, 0.0599, 0.0044, -0.0173, 0.0187, 0.0445, -0.0243, 0.0357, -0.0377, 0.0579, 0.0305, -0.018, -0.0315, 0.0107, -0.0527, -0.0277, 0.0266, 0.0043, -0.0425, 0.0278, -0.0169, -0.0178, 0.0032, 0.0655, -0.0373, 0.0016, 0.0429, 0.0921, 0.0877, -0.0214, -0.0283, -0.0249, -0.0186, -0.0068, -0.0608, 0.0491, -0.0623, 0.0761, 0.0631, -0.0874, 0.0466, 0.0276, 0.0892, -0.0293, -0.0068, -0.0808, -0.0685, 0.0088, -0.0491, -0.0329, 0.0323, -0.0315, 0.067, 0.0044, 0.0123, 0.0436, -0.0455, 0.0186, 0.0901, -0.1413, -0.035, 0.0167, -0.0246, 0.007, 0.0688, -0.0114, 0.0064, -0.0793, -0.0039, 0.0202, -0.0299, -0.065, 0.0165, -0.0481, 0.0698, -0.0193, 0.0, 0.0007, 0.0428, 0.0979, 0.0409, 0.0625, 0.113, 0.0485, 0.004, -0.0494, -0.0671, -0.0428, -0.102, 0.013, 0.0127, 0.0292, 0.0092, 0.0244, 0.0062, -0.0011, -0.0187, 0.0447, 0.042, 0.0175, -0.0459, 0.0203, -0.0074, 0.0338, 0.0745, -0.116, 0.0124, 0.058, -0.0277, 0.0151, -0.0158, -0.0472, 0.0573, -0.0434, 0.0561, 0.0062, 0.0299, 0.0666, -0.0391, 0.0466, 0.1004, -0.0309, -0.0857, -0.0178, -0.0327, -0.0469, -0.0422, 0.0175, -0.0668, -0.0782, -0.0456, 0.0058, -0.0122, -0.003, -0.0247, -0.0611, -0.054, -0.049, 0.0531, -0.0063, 0.072, -0.035, -0.0296, -0.0538, 0.0211, -0.0235, -0.0074, -0.0172, 0.0641, 0.0109, 0.065, -0.1117, -0.029, -0.0223, -0.0223, -0.026, 0.0126, -0.0317, -0.0304, 0.0688, 0.0179, 0.0414, 0.0946, -0.023, 0.0868, 0.0081, -0.004, 0.1146, 0.071, 0.0314, 0.0455, -0.0336, -0.0, 0.0361, 0.0507, -0.0212, 0.0181, -0.0055, 0.0554, 0.0128, 0.018, -0.0363, 0.0181, 0.0431, -0.0005, 0.0432, 0.0186, 0.0467, -0.0483, -0.0095, 0.1291, -0.0334, 0.0679, -0.0274, 0.0403, 0.0024, 0.0402, 0.0606, -0.1634, -0.0763, 0.0033, -0.0046, 0.0177, -0.0416, 0.0038, 0.0116, -0.0414, -0.0667, 0.0369, 0.0182, 0.0009, -0.1122, -0.0097, -0.016, -0.0033, -0.0174, 0.0039, 0.0239, -0.104, 0.0734, -0.0625, 0.0115, 0.0263, -0.0553, -0.0242, 0.0585, -0.0054, 0.0014, 0.0136, -0.1013, -0.0353, -0.0644, 0.0024, -0.1069, -0.1136, 0.0482, 0.042],
    "a place to keep my books": [-0.0081, -0.0177, -0.0435, 0.0458, -0.0369, 0.0136, 0.0125, -0.0087, 0.103, 0.0474, 0.0149, 0.0897, 0.0772, -0.0635, -0.0328, -0.025, -0.0402, -0.0388, 0.0065, -0.043, -0.0654, 0.1162, 0.0413, 0.0354, -0.0395, 0.0244, -0.0453, -0.0038, -0.0279, -0.0385, 0.0209, -0.0405, -0.0336, -0.0163, 0.0491, 0.0584, 0.0276, -0.0592, 0.0751, -0.0473, -0.036, -0.0149, 0.0034, 0.0422, -0.0365, 0.0389, 0.0242, -0.0131, 0.0538, 0.0561, 0.0598, 0.0329, -0.063, -0.0235, -0.0099, 0.0461, 0.0244, -0.0573, -0.0342, -0.0271, 0.144, -0.0091, -0.0476, 0.0393, -0.0138, 0.042, 0.0064, 0.1698, 0.0186, -0.0871, -0.0593, 0.0408, 0.0463, 0.0973, 0.0473, -0.0622, 0.0047, -0.0802, 0.0603, 0.0151, -0.0785, -0.067, 0.0629, 0.0152, -0.0543, -0.0658, 0.0586, -0.0616, -0.0066, -0.0243, 0.0587, -0.0147, 0.0758, 0.0046, -0.054, -0.0104, 0.0249, 0.0035, 0.0322, 0.0752, 0.0303, 0.0782, 0.0641, 0.0216, -0.0356, -0.0481, -0.0407, -0.0317, -0.0334, -0.0672, -0.0498, 0.0006, -0.0575, 0.0666, 0.0047, -0.0014, 0.1022, 0.0724, 0.0762, -0.0073, -0.0277, 0.0824, 0.0016, 0.0038, -0.0124, -0.0416, -0.0355, -0.0, 0.009, 0.0369, -0.0555, 0.0307, 0.0704, -0.0081, 0.0104, 0.0337, -0.0467, -0.0381, 0.0465, 0.0367, -0.0339, 0.0442, 0.0351, 0.0672, 0.0118, -0.0353, 0.0239, -0.0619, -0.0809, -0.0343, 0.0172, 0.007, 0.0275, 0.0015, -0.009, 0.0119, -0.0254, 0.017, -0.01, -0.0249, 0.0243, -0.1361, 0.0283, 0.0389, -0.061, -0.0089, 0.0896, -0.0104, -0.0374, 0.0087, 0.0225, 0.0599, 0.0487, 0.0524, 0.0852, 0.0449, 0.0656, 0.023, -0.0413, -0.1133, -0.0985, -0.0011, -0.0194, -0.0462, -0.0215, -0.0038, 0.0852, -0.0369, 0.045, 0.0759, 0.0361, 0.0018, 0.0132, -0.0592, -0.0305, -0.0086, 0.0545, -0.0372, -0.0734, -0.0459, 0.0628, -0.0141, -0.0325, 0.0221, -0.1192, 0.0078, -0.1113, -0.0952, 0.0532, -0.0866, -0.0597, 0.0784, 0.0349, -0.0297, 0.0436, -0.1214, -0.0765, -0.0391, -0.032, 0.0414, 0.0287, -0.0584, -0.0373, 0.0, 0.0664, -0.1441, -0.0305, 0.0606, -0.0066, 0.0288, -0.0372, 0.007, -0.04, 0.0258, -0.1317, 0.0225, 0.0333, 0.0284, -0.0119, -0.0349, 0.0647, -0.0354, -0.0414, -0.0371, -0.0934, 0.017, 0.0359, 0.0252, 0.0518, -0.0055, -0.0643, -0.0684, -0.0614, 0.0207, -0.0458, -0.0948, -0.0187, 0.0362, -0.0649, -0.0314, 0.0118, -0.0018, -0.0614, 0.0042, 0.0433, -0.0098, -0.0152, 0.0343, 0.01, -0.019, -0.047, 0.0461, 0.0478, -0.024, -0.022, -0.0297, 0.0178, -0.1122, 0.0057, 0.096, -0.0295, 0.0373, 0.0478, 0.0228, -0.0464, 0.0225, -0.0275, 0.0951, -0.0492, -0.0818, -0.0122, 0.046, -0.045, 0.0474, -0.039, 0.0179, 0.007, -0.0009, -0.0631, 0.0841, 0.0981, -0.002, -0.0174, 0.0178, -0.0305, 0.0028, -0.0776, 0.0218, 0.0386, -0.0851, 0.0507, -0.0084, -0.005, -0.0849, 0.0495, 0.0803, -0.0925, -0.0301, 0.0105, -0.0, -0.0115, 0.0183, 0.0092, 0.0432, -0.0767, -0.0492, 0.1178, 0.0182, 0.0053, 0.0543, 0.0616, -0.0565, 0.0031, -0.0249, -0.0511, 0.0278, 0.0827, -0.0739, -0.0335, 0.0519, 0.0446, 0.0117, 0.0802, -0.0036, 0.0166, 0.0412, 0.0948, 0.0222, 0.0551, 0.0128, 0.0361, 0.057, 0.0412, -0.0112, -0.0067, -0.0074, -0.0698, 0.0261, -0.0085, -0.0083, -0.0433, -0.0314, 0.0339, 0.0365, 0.019, -0.0105, 0.1076, 0.0424, 0.0494, 0.0421, -0.0896, -0.021, 0.1009, 0.0544, 0.0149, -0.0134, -0.0195, 0.0249, -0.0727, 0.0307, -0.0067, -0.0433, -0.1097, 0.0075],
    "click and scroll quickly at my desk": [-0.0462, -0.0389, -0.0024, -0.0005, 0.0933, 0.0251, 0.062, 0.0198, 0.0028, -0.0193, -0.0021, 0.0411, -0.0271, 0.0229, -0.0318, -0.0305, 0.0097, 0.0296, -0.0602, 0.0023, -0.036, -0.1024, -0.0181, 0.0013, -0.0482, -0.0255, -0.0584, -0.0661, -0.0386, -0.0283, -0.0609, 0.0276, 0.0704, 0.0148, -0.0937, -0.0431, -0.0618, -0.0443, 0.0805, -0.0121, -0.0469, -0.0667, 0.0672, 0.0616, 0.039, -0.0351, -0.0023, -0.0022, 0.0763, 0.0728, -0.0161, -0.0364, 0.0461, -0.0241, -0.0021, 0.0463, 0.0127, 0.012, 0.0532, 0.0479, 0.0195, -0.0547, 0.0121, 0.0711, 0.0012, 0.0519, 0.0015, -0.0003, -0.0551, 0.0922, -0.0306, -0.0042, -0.0201, 0.0831, -0.001, -0.0901, -0.0216, -0.0825, 0.0371, 0.035, 0.0012, -0.0062, -0.0162, 0.0877, 0.0807, 0.0294, 0.0185, 0.046, 0.0015, -0.0779, 0.0168, -0.0453, -0.0117, 0.0277, -0.052, -0.0452, 0.0566, -0.0229, -0.0462, 0.0099, 0.0387, 0.0547, 0.0917, 0.011, -0.0665, -0.0102, 0.0555, 0.0127, -0.1089, 0.0384, -0.0345, -0.0612, -0.0628, -0.0459, -0.0357, -0.0033, -0.0528, -0.0281, 0.0956, -0.0305, 0.0505, 0.0468, -0.1256, -0.0684, 0.0534, -0.0435, -0.028, -0.0, 0.027, -0.0591, -0.0779, -0.0388, 0.0106, -0.018, 0.0232, -0.0107, -0.0746, 0.0053, 0.0583, -0.0551, -0.0083, 0.0426, -0.0004, -0.0699, 0.029, 0.0746, -0.08, -0.0153, -0.0013, -0.0611, -0.0441, -0.0297, 0.032, 0.0919, -0.049, 0.0003, 0.0615, 0.0517, -0.0423, 0.0396, -0.0866, -0.0811, -0.0612, -0.0415, -0.0243, 0.0164, 0.0972, -0.0433, -0.0922, -0.0364, 0.0483, -0.0093, -0.0135, 0.0505, -0.0007, 0.0397, 0.0265, -0.0363, 0.0029, -0.0087, -0.033, -0.0163, 0.0353, -0.0335, 0.0074, 0.0893, 0.0167, 0.1187, -0.0321, 0.0045, -0.0326, 0.0192, 0.0087, 0.019, 0.0033, 0.0593, 0.0098, -0.043, 0.0494, -0.0861, 0.0515, -0.0005, 0.0136, 0.0348, -0.0112, -0.074, -0.0501, -0.0062, 0.0039, -0.0707, -0.0083, -0.0117, 0.0184, -0.0804, -0.0499, 0.0004, -0.069, 0.0017, -0.054, 0.0149, 0.0337, -0.0555, -0.0976, 0.0, 0.0581, -0.0107, -0.038, 0.0333, -0.0331, 0.1637, 0.0404, 0.004, -0.0574, 0.0323, 0.0311, 0.0459, -0.0018, 0.0375, 0.0813, 0.1177, 0.01, 0.0565, -0.1129, -0.0203, -0.006, -0.1367, -0.024, 0.0663, 0.0341, -0.0328, 0.06, 0.0025, 0.0251, -0.0059, -0.0896, 0.026, -0.105, 0.0062, 0.1038, 0.0632, -0.0297, -0.0436, -0.0259, 0.025, 0.0649, -0.0199, 0.0611, 0.0134, 0.0129, -0.0004, -0.075, 0.0428, 0.0043, 0.0573, -0.0424, -0.0227, 0.0946, -0.1674, -0.023, 0.0544, -0.0356, -0.0204, 0.0376, -0.0327, -0.0141, -0.0433, -0.0498, 0.0097, 0.0188, 0.0028, 0.0127, -0.002, -0.0131, 0.0724, -0.0114, 0.0321, 0.0044, -0.0568, -0.0067, -0.0497, 0.1048, 0.0283, 0.007, -0.0496, 0.1611, 0.0631, 0.074, -0.1096, -0.0559, 0.0565, -0.091, -0.0334, -0.0004, -0.0484, -0.0357, 0.0101, -0.0014, 0.0324, -0.0258, -0.0, -0.0527, -0.0251, 0.066, -0.0564, 0.078, 0.0063, 0.0161, 0.1032, -0.0367, -0.0206, 0.0483, -0.0636, 0.0447, 0.0993, 0.1134, 0.0035, 0.0196, 0.0386, -0.0047, -0.007, 0.0818, 0.0003, 0.0348, 0.0098, -0.0178, 0.039, 0.0001, 0.1138, 0.0356, 0.0188, 0.0046, 0.0434, -0.1246, -0.0416, 0.0274, -0.0022, 0.0312, -0.0288, -0.0337, -0.0231, -0.0091, 0.0018, 0.029, 0.0421, -0.0926, -0.0237, 0.0342, -0.0432, 0.0142, -0.0099, -0.0208, 0.011, 0.1121, 0.0027, -0.0543, 0.0212, -0.0195, -0.0161, -0.0359, 0.0597, 0.042, 0.1117, -0.006, 0.0393],
    "portable workstation for a student": [0.0149, 0.053, 0.0583, -0.0319, -0.0129, -0.0, 0.0201, 0.103, -0.0326, -0.0087, 0.07, 0.0773, 0.0346, 0.0515, -0.0468, -0.0332, 0.0146, -0.0498, 0.1047, 0.0215, -0.0017, 0.0239, -0.0804, -0.028, 0.072, 0.0296, 0.0652, -0.0392, -0.0011, -0.0038, -0.0533, -0.0505, -0.034, -0.0244, 0.0406, -0.0372, 0.0841, -0.0047, -0.0446, -0.0812, -0.051, 0.0286, 0.0109, 0.0512, -0.0047, -0.0097, -0.0294, -0.0869, 0.0416, 0.0056, 0.0202, -0.057, 0.0332, -0.0086, -0.0396, -0.0841, 0.0426, 0.0067, 0.03, -0.079, -0.0058, -0.0169, 0.015, -0.0149, -0.0567, -0.06, -0.0247, 0.0317, 0.0627, 0.0079, -0.081, -0.0417, 0.0027, 0.0314, 0.0033, 0.0091, -0.004, -0.0408, 0.0671, 0.0683, -0.0139, 0.0785, -0.0545, -0.0028, 0.029, -0.0416, -0.0091, 0.0211, -0.0276, -0.1231, 0.0276, 0.0511, -0.0127, -0.0158, 0.0237, -0.139, 0.0701, -0.0023, -0.0171, 0.0165, 0.0139, 0.0402, 0.1314, -0.0338, -0.1021, -0.0301, 0.0208, -0.0864, 0.0239, -0.0295, -0.0544, -0.0051, -0.1039, 0.0109, -0.0179, -0.0352, -0.0364, 0.0422, 0.002, 0.0442, 0.0212, -0.028, 0.0642, -0.0132, 0.051, -0.057, -0.0018, -0.0, 0.035, 0.0728, -0.0799, 0.0535, 0.063, -0.0704, 0.058, 0.0613, 0.0001, 0.0318, -0.0, 0.0933, -0.0047, 0.0767, 0.0815, -0.0468, 0.0572, 0.01, 0.0225, 0.0389, -0.0283, -0.0669, 0.025, -0.0124, 0.0365, -0.069, -0.0444, 0.0377, 0.1161, -0.0017, -0.0296, -0.0618, -0.0433, -0.0404, -0.0038, -0.0145, -0.0874, -0.0361, 0.0773, -0.0771, -0.0428, 0.0069, 0.1074, -0.013, 0.0492, 0.0144, 0.0274, 0.0389, 0.0419, -0.0258, -0.0957, -0.0087, -0.0233, -0.0293, 0.0, -0.0511, 0.043, 0.0443, 0.0724, 0.0301, -0.0835, 0.1071, -0.0097, 0.0443, -0.0108, -0.0195, 0.0237, 0.0077, 0.0429, -0.0435, 0.0416, -0.0197, 0.0083, -0.0548, 0.0025, 0.0729, -0.0789, -0.0546, -0.1322, -0.0097, -0.0467, -0.122, 0.0045, 0.0533, -0.0093, 0.0434, -0.0709, -0.0116, -0.0342, 0.0658, 0.115, -0.0246, -0.0795, 0.0701, -0.0178, 0.0, 0.015, -0.0227, 0.0385, -0.0489, 0.0644, 0.0366, 0.0192, 0.0006, -0.0901, -0.0254, -0.0867, -0.0337, 0.0107, 0.0305, 0.0573, 0.0708, -0.0343, 0.0058, -0.0066, 0.0029, -0.011, 0.0626, -0.0025, -0.0305, 0.0095, -0.0012, -0.0412, -0.0695, -0.0261, 0.088, -0.037, -0.0656, 0.0133, 0.0158, 0.0867, -0.0453, -0.0219, 0.0497, -0.0261, 0.0014, 0.0428, 0.007, 0.0136, -0.0108, 0.1061, -0.0301, -0.0776, 0.0157, 0.0353, -0.0192, 0.015, -0.0335, 0.0486, -0.0591, 0.0191, -0.0506, -0.0094, 0.0013, 0.0022, -0.0137, 0.0355, -0.0941, 0.0231, 0.0505, -0.1269, 0.0011, 0.0473, 0.0569, -0.0397, 0.0369, -0.0249, 0.0447, 0.031, -0.0398, -0.0072, 0.0575, 0.0907, -0.029, 0.0169, 0.0076, 0.047, -0.0294, -0.0215, -0.047, -0.0391, -0.0752, -0.0226, -0.0785, -0.0293, -0.0237, 0.0054, 0.0027, -0.0284, -0.003, 0.0512, -0.0, -0.0206, -0.0058, -0.0145, 0.0364, -0.1404, -0.0807, 0.0913, -0.0404, 0.0876, 0.0588, 0.0425, -0.1256, 0.0542, 0.0094, 0.0462, 0.1266, 0.0371, 0.0704, 0.0055, -0.0199, 0.045, -0.0663, 0.0712, 0.1026, 0.0068, -0.0195, -0.0341, 0.0247, 0.0341, 0.0176, 0.0082, 0.0212, -0.065, -0.0083, 0.0335, -0.0772, -0.0193, 0.0196, 0.0716, 0.061, 0.0629, -0.0416, -0.1008, -0.0077, 0.0591, -0.0628, -0.0823, -0.0889, 0.0127, 0.1518, 0.0165, 0.0029, 0.0002, -0.042, 0.0401, 0.0541, -0.0058, 0.0521, -0.0573, 0.0376, -0.0384, 0.0507, -0.0016, 0.0585],
};

// Embedding text used for each product (same fields as the document):
//   1: iPhone 16 by Apple. Latest Apple smartphone. Categories: Electronics, Smartphones. Tags: apple, iphone, smartphone, 5g, ios, camera.
//   2: Galaxy S25 by Samsung. Samsung flagship smartphone. Categories: Electronics, Smartphones. Tags: samsung, galaxy, smartphone, 5g, android, camera.
//   3: MX Master 3S by Logitech. Wireless productivity mouse. Categories: Electronics, Accessories. Tags: logitech, mouse, wireless, productivity, office.
//   4: MacBook Air M4 by Apple. Lightweight Apple laptop. Categories: Electronics, Laptops. Tags: apple, macbook, laptop, ultrabook, macos, productivity.
//   5: Air Max 270 by Nike. Nike lifestyle running shoe. Categories: Fashion, Footwear. Tags: nike, sneakers, running, lifestyle, shoes.
//   6: Ultraboost Light by Adidas. Adidas performance running shoe. Categories: Fashion, Footwear. Tags: adidas, running, shoes, sports, boost.
//   7: KALLAX Shelf by IKEA. Modular storage shelf. Categories: Home. Tags: ikea, shelf, storage, furniture, home, organiser.

// 5.1 Store the embeddings on the product documents (validated: exactly 384 numbers)
Object.entries(PRODUCT_EMBEDDINGS).forEach(([productId, vector]) => {
    db.product_catalog.updateOne(
        { product_id: Number(productId) },
        { $set: { embedding: vector.map(x => Double(x)), embedding_model: "all-MiniLM-L6-v2" } });
});
print("\n5.1 Products with an embedding: " +
      db.product_catalog.countDocuments({ embedding: { $size: 384 } }) + " of " +
      db.product_catalog.countDocuments());

// 5.2 Similarity stage: dot product of the stored vector and the query vector
function similarityStage(queryVector) {
    return { $addFields: { similarity: { $reduce: {
        input: { $range: [0, 384] },
        initialValue: 0,
        in: { $add: ["$$value",
                     { $multiply: [{ $arrayElemAt: ["$embedding", "$$this"] },
                                   { $arrayElemAt: [queryVector, "$$this"] }] }] }
    } } } };
}

// Reusable semantic search: optional metadata filter (applied BEFORE the
// vector scoring, as in a vector database's filtered search), top-k results,
// and a minimum similarity so unrelated products are not returned.
function semanticSearch(queryText, { k = 3, minScore = 0.25, filter = {} } = {}) {
    const queryVector = QUERY_EMBEDDINGS[queryText];
    return db.product_catalog.aggregate([
        { $match: { status: "ACTIVE", embedding: { $exists: true }, ...filter } },
        similarityStage(queryVector),
        { $match: { similarity: { $gte: minScore } } },
        { $sort: { similarity: -1 } },
        { $limit: k },
        { $project: { _id: 0, name: 1, "price.min": 1, similarity: { $round: ["$similarity", 3] } } }
    ]).toArray();
}

// 5.3 Keyword search vs vector search on queries that share NO words with
//     any product: $text finds nothing, vector search finds the right items.
Object.keys(QUERY_EMBEDDINGS).forEach(q => {
    const keywordHits = db.product_catalog.countDocuments({ $text: { $search: q } });
    print(`\n5.3 "${q}"  ->  keyword ($text) results: ${keywordHits}`);
    show(`5.3 Vector search: "${q}"`, semanticSearch(q));
});

// 5.4 Hybrid search: vector similarity + metadata filter (price and category)
show('5.4 "jogging trainers" under ₹14,000 (vector search + filter)',
    semanticSearch("jogging trainers", { filter: { categories: "Footwear", "price.min": { $lt: 14000 } } }));

// 5.5 "More like this": nearest neighbours of a product's own embedding
//     (compare with the tag-based similarity in 4.3)
function semanticallySimilar(productId, k = 2) {
    const base = db.product_catalog.findOne({ product_id: productId }, { embedding: 1 });
    return db.product_catalog.aggregate([
        { $match: { product_id: { $ne: productId }, embedding: { $exists: true } } },
        similarityStage(base.embedding),
        { $sort: { similarity: -1 } },
        { $limit: k },
        { $project: { _id: 0, name: 1, similarity: { $round: ["$similarity", 3] } } }
    ]).toArray();
}
show("5.5 Semantically similar to iPhone 16", semanticallySimilar(1));
show("5.5 Semantically similar to Air Max 270", semanticallySimilar(5));

// 5.6 Validation: an embedding with the wrong number of dimensions is rejected
try {
    db.product_catalog.updateOne({ product_id: 7 }, { $set: { embedding: [Double(0.1), Double(0.2), Double(0.3)] } });
} catch (e) { print("\n5.6 Rejected (3-dimensional embedding instead of 384): " + e.message); }

print("\nDone.");
