# Return Rate Root Cause Analyzer
## Quick Commerce Analytics | Python + MySQL + Power BI

---

## Business Problem
Quick commerce companies (Blinkit, Zepto, Swiggy Instamart) lose **15–28% margin on returns**.
This project finds which **product categories, delivery slots, and customer segments** drive
the most returns — with actionable root causes, not just numbers.

---

## Tech Stack

- SQL (MySQL)
- Power BI
- Python
- Excel

---

## Dataset Summary
| File | Rows | Description |
|------|------|-------------|
| products.csv | 459 | SKU master — category, brand, perishability |
| customers.csv | 18,000 | Customer profiles with tenure & segments |
| delivery_slots.csv | 6 | Time-window definitions with SLA data |
| orders.csv | 80,000 | 24 months of orders (Jul 2022 – Jun 2024) |
| returns.csv | 16,713 | Return events with reasons & financial loss |

**Total financial loss simulated: ₹5.97 Million**

---

## Project File Structure
```
return_rate_analyzer/
│
├── data/                             
│   ├── products.csv
│   ├── customers.csv
│   ├── delivery_slots.csv
│   ├── orders.csv
│   └── returns.csv
│
├── mysql_scripts/                   
│   ├── 01_create_schema.sql         
│   ├── 03_business_queries.sql  
│   └── 04_views_and_procedures.sql  
│
├── python_scripts/                  
│   ├── 02_load_data_to_mysql.py     
│   └── 03_eda_analysis.py           
│        
│
├── generate_all_data.py             
├── requirements.txt              
└── README.md                       
```

---

## Key Business Insights

### Root Cause 1 — Perishable Product Quality
- Perishables drive **60%+ of total losses**
- "Damaged" + "Expired" = 44% of all returns
- **Fix**: Cold-chain SLA by sub-category; expiry scan before dispatch

### Root Cause 2 — Prime Evening Slot Overload
- 30% SLA breach rate in 6–9 PM slot
- Late deliveries return at **2× the rate** of on-time
- **Fix**: Cap Prime Evening orders; add 20% delivery agents 5–9 PM

### Root Cause 3 — New Customer Onboarding Gap
- New users return 10+ pct points more than Champions
- They often cite "Quality Not as Expected" — expectation mismatch
- **Fix**: Curate first-3-order SKU list; add quality guarantee messaging

### Root Cause 4 — City-Level Ops Variance
- Delhi & Mumbai highest returns; Bengaluru benchmarks best practice
- **Fix**: City-specific ops playbook

### Estimated Financial Impact of Fixes
| Fix | Return Rate Reduction |
|-----|-----------------------|
| Cold-chain for perishables | −4 to −6 pct points |
| Prime Evening capacity cap | −2 to −3 pct points |
| New customer onboarding | −1.5 to −2 pct points |
| SKU audit (top 25) | −0.5 to −1 pct point |
| **Total** | **−8 to −12 pct points** |

Reducing returns from 21% to 12% on 80K orders saves approximately **₹2M–₹2.8M**.


