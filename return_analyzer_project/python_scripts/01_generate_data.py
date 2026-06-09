"""
Generates all 5 clean CSV datasets for the Return Rate Root Cause project.
Run: python generate_all_data.py
"""
import pandas as pd
import numpy as np
from faker import Faker
import random
from datetime import datetime, timedelta
from pathlib import Path

fake = Faker("en_IN")
np.random.seed(42)
random.seed(42)

DATA = Path("data")
DATA.mkdir(exist_ok=True)

N_ORDERS    = 80000
N_CUSTOMERS = 18000
START_DATE  = datetime(2022, 7, 1)
END_DATE    = datetime(2024, 6, 30)   # 24 months

CITIES = {
    "Mumbai": 0.21, "Delhi": 0.20, "Bengaluru": 0.17,
    "Hyderabad": 0.11, "Pune": 0.10, "Chennai": 0.09,
    "Kolkata": 0.07, "Ahmedabad": 0.05,
}

CATEGORIES = {
    "Fruits & Vegetables": {
        "subs": ["Fresh Fruits","Exotic Vegetables","Leafy Greens","Root Vegetables","Herbs & Seasonings"],
        "base_return": 0.23, "avg_price": 115, "perishable": True
    },
    "Dairy & Eggs": {
        "subs": ["Milk","Cheese","Paneer","Eggs","Butter","Curd & Yogurt","Ghee"],
        "base_return": 0.15, "avg_price": 90, "perishable": True
    },
    "Meat & Seafood": {
        "subs": ["Chicken","Mutton","Fish","Prawns & Shrimp","Other Seafood"],
        "base_return": 0.20, "avg_price": 360, "perishable": True
    },
    "Frozen Foods": {
        "subs": ["Ice Cream","Frozen Vegetables","Ready to Cook","Frozen Snacks","Frozen Meat"],
        "base_return": 0.18, "avg_price": 220, "perishable": True
    },
    "Bakery & Bread": {
        "subs": ["Bread & Buns","Biscuits & Cookies","Cakes & Pastries","Muffins","Rusks & Toasts"],
        "base_return": 0.09, "avg_price": 78, "perishable": False
    },
    "Snacks & Namkeen": {
        "subs": ["Chips & Crisps","Namkeen","Popcorn","Nuts & Dry Fruits","Energy Bars"],
        "base_return": 0.06, "avg_price": 105, "perishable": False
    },
    "Beverages": {
        "subs": ["Juices","Soft Drinks","Energy Drinks","Tea & Coffee","Health Drinks","Water"],
        "base_return": 0.05, "avg_price": 95, "perishable": False
    },
    "Staples & Grains": {
        "subs": ["Rice","Atta & Flour","Dal & Pulses","Cooking Oil","Sugar & Salt","Spices"],
        "base_return": 0.04, "avg_price": 175, "perishable": False
    },
    "Personal Care": {
        "subs": ["Skincare","Hair Care","Oral Care","Body Wash","Deodorants","Feminine Hygiene"],
        "base_return": 0.07, "avg_price": 310, "perishable": False
    },
    "Household Essentials": {
        "subs": ["Cleaning Liquids","Detergents","Dishwash","Floor Cleaners","Fresheners","Tissues & Wipes"],
        "base_return": 0.05, "avg_price": 185, "perishable": False
    },
    "Baby Care": {
        "subs": ["Diapers","Baby Food","Baby Wipes","Baby Lotion","Baby Accessories"],
        "base_return": 0.08, "avg_price": 470, "perishable": False
    },
    "Pet Care": {
        "subs": ["Dog Food","Cat Food","Pet Treats","Pet Accessories"],
        "base_return": 0.06, "avg_price": 290, "perishable": False
    },
}

SLOTS = {
    "Early Morning (6–9 AM)":   {"breach_rate": 0.07, "weight": 0.7},
    "Morning (9 AM–12 PM)":     {"breach_rate": 0.11, "weight": 1.3},
    "Afternoon (12–3 PM)":      {"breach_rate": 0.17, "weight": 1.0},
    "Evening (3–6 PM)":         {"breach_rate": 0.21, "weight": 1.5},
    "Prime Evening (6–9 PM)":   {"breach_rate": 0.30, "weight": 2.0},
    "Night (9 PM–12 AM)":       {"breach_rate": 0.13, "weight": 0.8},
}

RETURN_REASONS = [
    ("Damaged Product",         0.27),
    ("Wrong Item Delivered",    0.18),
    ("Expired or Near-Expiry",  0.17),
    ("Quality Not as Expected", 0.14),
    ("Item Missing in Order",   0.10),
    ("Changed Mind",            0.07),
    ("Duplicate Order",         0.04),
    ("Other",                   0.03),
]

BRANDS = {
    "Budget":  ["FreshMart","DailyBasket","QuickChoice","ValueCart","HomeFirst"],
    "Mid":     ["NatureFresh","GoodLife","OrganicPlus","PureHome","FreshZone"],
    "Premium": ["GourmetSelect","FineChoice","PremiumOrg","LuxeCart","EliteGrocers"],
}

PAYMENT_METHODS = ["UPI", "UPI", "UPI", "Credit Card", "Debit Card", "Cash on Delivery", "Wallet"]
ORDER_SOURCES   = ["App", "App", "App", "Web", "Web", "Partner API"]

# ── 1. PRODUCTS (500 SKUs) ─────────────────────────────────────────────────
print("Generating products.csv ...")
rows = []
sku_num = 1001
for cat, meta in CATEGORIES.items():
    per_sub = max(int(500 / (len(CATEGORIES) * len(meta["subs"]))), 2)
    for sub in meta["subs"]:
        for _ in range(per_sub):
            tier  = random.choices(["Budget","Mid","Premium"], weights=[40,40,20])[0]
            brand = random.choice(BRANDS[tier])
            price = round(max(12, np.random.normal(meta["avg_price"], meta["avg_price"]*0.28)), 2)
            rows.append({
                "sku_id":          f"SKU{sku_num:04d}",
                "product_name":    f"{brand} {sub} {random.choice(['Pack','Box','Bundle','Fresh','Select'])} {random.randint(1,5)*100}g",
                "brand":           brand,
                "brand_tier":      tier,
                "category":        cat,
                "sub_category":    sub,
                "mrp":             price,
                "selling_price":   round(price * random.uniform(0.80, 0.98), 2),
                "weight_grams":    random.choice([100,200,250,500,750,1000,1500,2000]),
                "is_perishable":   1 if meta["perishable"] else 0,
                "shelf_life_days": random.choice([2,3,5,7]) if meta["perishable"] else random.choice([90,180,365]),
                "base_return_rate":round(meta["base_return"] + np.random.uniform(-0.05, 0.05), 3),
                "is_active":       1,
            })
            sku_num += 1

products_df = pd.DataFrame(rows)
products_df.to_csv(DATA/"products.csv", index=False)
print(f"  ✓  {len(products_df):,} SKUs")

# ── 2. CUSTOMERS (18,000) ──────────────────────────────────────────────────
print("Generating customers.csv ...")
rows = []
for i in range(N_CUSTOMERS):
    join_dt     = START_DATE - timedelta(days=random.randint(0, 900))
    tenure      = (END_DATE - join_dt).days
    city        = random.choices(list(CITIES), weights=list(CITIES.values()))[0]
    if tenure < 30:    seg = "New"
    elif tenure < 90:  seg = "Growing"
    elif tenure < 365: seg = "Loyal"
    else:              seg = "Champion"

    rows.append({
        "customer_id":        f"CUS{i+1:06d}",
        "full_name":          fake.name(),
        "email":              fake.email(),
        "phone":              fake.phone_number()[:10],
        "city":               city,
        "pincode":            str(random.randint(110001, 600099)),
        "join_date":          join_dt.strftime("%Y-%m-%d"),
        "tenure_days":        tenure,
        "segment":            seg,
        "age_group":          random.choices(["18-24","25-34","35-44","45-54","55+"], weights=[15,35,25,15,10])[0],
        "gender":             random.choices(["Male","Female","Other"], weights=[48,50,2])[0],
        "has_subscription":   random.choices([0,1], weights=[72,28])[0],
        "preferred_slot":     random.choice(list(SLOTS.keys())),
        "avg_order_value":    round(np.random.lognormal(5.5, 0.55), 2),
        "lifetime_orders":    random.randint(1, 250),
        "referral_source":    random.choice(["Organic","Google Ad","Friend Referral","Instagram","Offer Code","Influencer"]),
    })

customers_df = pd.DataFrame(rows)
customers_df.to_csv(DATA/"customers.csv", index=False)
print(f"  ✓  {len(customers_df):,} customers")

# ── 3. DELIVERY SLOTS ─────────────────────────────────────────────────────
print("Generating delivery_slots.csv ...")
slots_rows = []
for i, (name, meta) in enumerate(SLOTS.items()):
    slots_rows.append({
        "slot_id":            f"SLT{i+1:02d}",
        "slot_name":          name,
        "slot_start":         ["06:00","09:00","12:00","15:00","18:00","21:00"][i],
        "slot_end":           ["09:00","12:00","15:00","18:00","21:00","00:00"][i],
        "sla_target_minutes": 20,
        "sla_breach_rate":    meta["breach_rate"],
        "demand_weight":      meta["weight"],
        "recommended_capacity":"Low" if meta["weight"]<0.9 else "Medium" if meta["weight"]<1.6 else "High",
    })
slots_df = pd.DataFrame(slots_rows)
slots_df.to_csv(DATA/"delivery_slots.csv", index=False)
print(f"  ✓  {len(slots_df)} slots")

# ── 4. ORDERS (80,000) ────────────────────────────────────────────────────
print("Generating orders.csv  (80,000 rows — ~60 sec) ...")

slot_names   = list(SLOTS.keys())
slot_weights = [v["weight"] for v in SLOTS.values()]
sku_base     = dict(zip(products_df["sku_id"], products_df["base_return_rate"]))
perishable_s = set(products_df[products_df["is_perishable"]==1]["sku_id"])

CITY_RETURN_BIAS = {
    "Mumbai":0.025,"Delhi":0.030,"Bengaluru":-0.015,
    "Hyderabad":0.010,"Pune":-0.010,"Chennai":0.005,
    "Kolkata":0.020,"Ahmedabad":-0.020,
}
SEG_RETURN_BIAS = {"New":0.105,"Growing":0.050,"Loyal":0.000,"Champion":-0.030}

def return_prob(sku_id, slot, sla_breach, seg, city, perishable, dow, tenure, discount_pct):
    p = sku_base.get(sku_id, 0.10)
    p += SLOTS[slot]["breach_rate"] * 0.38
    if sla_breach: p += 0.12
    p += SEG_RETURN_BIAS.get(seg, 0)
    p += CITY_RETURN_BIAS.get(city, 0)
    if perishable:  p += 0.045
    if dow in ("Saturday","Sunday"): p += 0.020
    if tenure < 14: p += 0.04   # very new customers
    if discount_pct > 0.25: p += 0.015  # heavily discounted orders
    return float(np.clip(p, 0.02, 0.88))

orders_rows = []
for i in range(N_ORDERS):
    cust    = customers_df.sample(1).iloc[0]
    sku     = products_df.sample(1).iloc[0]
    slot    = random.choices(slot_names, weights=slot_weights)[0]
    odate   = START_DATE + timedelta(days=random.randint(0,(END_DATE-START_DATE).days))
    qty     = random.choices([1,2,3,4,5,6], weights=[50,26,12,7,3,2])[0]
    mrp     = sku["mrp"]
    disc    = round(mrp * random.uniform(0, 0.35), 2)
    disc_pct= disc / mrp if mrp > 0 else 0
    paid    = round((mrp - disc) * qty, 2)
    breach  = 1 if random.random() < SLOTS[slot]["breach_rate"] else 0
    del_min = max(7, int(np.random.normal(20 if not breach else 46, 7)))
    perishable = 1 if sku["sku_id"] in perishable_s else 0

    row = {
        "order_id":          f"ORD{i+1:07d}",
        "customer_id":       cust["customer_id"],
        "sku_id":            sku["sku_id"],
        "category":          sku["category"],
        "sub_category":      sku["sub_category"],
        "brand_tier":        sku["brand_tier"],
        "city":              cust["city"],
        "pincode":           cust["pincode"],
        "order_date":        odate.strftime("%Y-%m-%d"),
        "order_month":       odate.strftime("%Y-%m"),
        "order_quarter":     f"Q{((odate.month-1)//3)+1} {odate.year}",
        "order_year":        odate.year,
        "order_dow":         odate.strftime("%A"),
        "is_weekend":        1 if odate.strftime("%A") in ("Saturday","Sunday") else 0,
        "delivery_slot":     slot,
        "quantity":          qty,
        "mrp":               round(mrp, 2),
        "discount_amount":   disc,
        "discount_pct":      round(disc_pct * 100, 1),
        "total_paid":        paid,
        "payment_method":    random.choice(PAYMENT_METHODS),
        "order_source":      random.choice(ORDER_SOURCES),
        "sla_breach":        breach,
        "delivery_minutes":  del_min,
        "customer_segment":  cust["segment"],
        "customer_tenure_days": cust["tenure_days"],
        "is_perishable":     perishable,
        "dark_store_id":     f"DS{random.randint(1,25):03d}",
        "delivery_agent_id": f"DA{random.randint(1,200):04d}",
    }
    p   = return_prob(sku["sku_id"], slot, breach, cust["segment"],
                      cust["city"], perishable, odate.strftime("%A"),
                      cust["tenure_days"], disc_pct)
    row["is_returned"]       = 1 if random.random() < p else 0
    row["return_probability"] = round(p, 4)
    orders_rows.append(row)

orders_df = pd.DataFrame(orders_rows)
orders_df.to_csv(DATA/"orders.csv", index=False)
n_ret = orders_df["is_returned"].sum()
print(f"  ✓  {len(orders_df):,} orders | {n_ret:,} returns ({n_ret/len(orders_df)*100:.1f}%)")

# ── 5. RETURNS (detail) ───────────────────────────────────────────────────
print("Generating returns.csv ...")
r_names, r_weights = zip(*RETURN_REASONS)
returned = orders_df[orders_df["is_returned"]==1].reset_index(drop=True)

ret_rows = []
for _, row in returned.iterrows():
    w = list(r_weights)
    if row["is_perishable"]:
        w[2] *= 2.8; w[0] *= 1.6
    if SLOTS[row["delivery_slot"]]["breach_rate"] > 0.20:
        w[0] *= 1.9
    if row["customer_segment"] == "New":
        w[3] *= 1.5   # quality not as expected
    total_w = sum(w)
    w = [x/total_w for x in w]
    reason = random.choices(r_names, weights=w)[0]

    ret_date = pd.to_datetime(row["order_date"]) + timedelta(
        days=random.choices([0,1,2,3,4,5,6,7], weights=[28,26,18,13,7,4,2,2])[0]
    )
    refund   = round(row["total_paid"] * random.uniform(0.82, 1.00), 2)
    rev_log  = round(random.uniform(28, 85), 2)
    ret_rows.append({
        "return_id":            f"RET{len(ret_rows)+1:07d}",
        "order_id":             row["order_id"],
        "customer_id":          row["customer_id"],
        "sku_id":               row["sku_id"],
        "category":             row["category"],
        "sub_category":         row["sub_category"],
        "brand_tier":           row["brand_tier"],
        "city":                 row["city"],
        "return_date":          ret_date.strftime("%Y-%m-%d"),
        "return_month":         ret_date.strftime("%Y-%m"),
        "days_to_return":       (ret_date - pd.to_datetime(row["order_date"])).days,
        "return_reason":        reason,
        "return_reason_group":  ("Logistics" if reason in ("Damaged Product","Item Missing in Order","Wrong Item Delivered")
                                  else "Quality" if reason in ("Expired or Near-Expiry","Quality Not as Expected")
                                  else "Customer"),
        "refund_amount":        refund,
        "reverse_logistics_cost": rev_log,
        "total_loss":           round(refund + rev_log, 2),
        "resolution_days":      random.choices([0,1,2,3,5,7,10], weights=[18,28,24,16,7,4,3])[0],
        "refund_mode":          random.choices(["Original Payment Method","Wallet Credit","Bank Transfer"], weights=[60,30,10])[0],
        "customer_segment":     row["customer_segment"],
        "delivery_slot":        row["delivery_slot"],
        "sla_breached":         row["sla_breach"],
        "is_perishable":        row["is_perishable"],
        "order_total_paid":     row["total_paid"],
        "dark_store_id":        row["dark_store_id"],
        "delivery_agent_id":    row["delivery_agent_id"],
    })

returns_df = pd.DataFrame(ret_rows)
returns_df.to_csv(DATA/"returns.csv", index=False)

print(f"  ✓  {len(returns_df):,} returns | Total loss ₹{returns_df['total_loss'].sum():,.0f}")
print()
print("=" * 52)
print("  ALL DATASETS READY")
print("=" * 52)
for f in sorted(Path("data").glob("*.csv")):
    sz = f.stat().st_size / 1024
    df_tmp = pd.read_csv(f)
    print(f"  {f.name:<25} {len(df_tmp):>7,} rows  {sz:>7.1f} KB")
