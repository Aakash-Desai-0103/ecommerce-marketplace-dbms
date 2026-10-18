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
                        }
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
        { _id: 0, name: 1, "variants.$": 1 }));

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

print("\nDone.");
