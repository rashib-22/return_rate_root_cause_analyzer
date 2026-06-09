-- =============================================================================
-- FILE  : 03_business_queries.sql
-- PROJECT: Return Rate Root Cause Analyzer — Quick Commerce
-- PURPOSE: 19 business intelligence queries answering every key return driver
-- HOW TO USE: Open in MySQL Workbench. Run each block one at a time (Ctrl+Enter)
-- =============================================================================

USE return_analyzer;

-- =============================================================================
-- BLOCK A  ─  EXECUTIVE KPIs
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q1. TOP-LEVEL KPIs  (single-row summary for leadership)
-- ANSWERS: What is our return rate? How much money are we losing?
-- EXPECTED: ~21% return rate, ₹5.97M total loss across 80K orders
-- ─────────────────────────────────────────────────────────────
SELECT
    FORMAT(COUNT(DISTINCT o.order_id), 0)                                     AS total_orders,
    FORMAT(COUNT(DISTINCT r.return_id), 0)                                    AS total_returns,
    CONCAT(ROUND(COUNT(DISTINCT r.return_id) * 100.0
           / COUNT(DISTINCT o.order_id), 2), '%')                             AS return_rate,
    CONCAT('₹', FORMAT(ROUND(SUM(o.total_paid) / 1000000, 2), 2), 'M')       AS gross_revenue,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.total_loss), 0) / 1000000, 2), 2), 'M')
                                                                               AS total_loss,
    CONCAT(ROUND(COALESCE(SUM(r.total_loss), 0) / SUM(o.total_paid) * 100, 2), '%')
                                                                               AS margin_erosion,
    CONCAT('₹', FORMAT(ROUND(COALESCE(AVG(r.total_loss), 0), 0), 0))         AS avg_loss_per_return,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.refund_amount), 0) / 1000000, 2), 2), 'M')
                                                                               AS total_refunds,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.reverse_logistics_cost), 0), 0), 0))
                                                                               AS total_logistics_cost
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id;


-- =============================================================================
-- BLOCK B  ─  CATEGORY DIMENSION  (Root Cause #1)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q2. RETURN RATE BY CATEGORY  ← ranked by financial loss
-- ANSWERS: Which product categories drive the most returns and losses?
-- EXPECTED: Fruits & Veg, Meat & Seafood, Frozen Foods lead in return rate.
--           Their total_loss_inr will be highest because they are also
--           high-volume and perishable — double damage.
-- ACTION  : Cold-chain quality gates, expiry scans before dispatch.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.category,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(SUM(o.total_paid) / 1000, 0)                                        AS revenue_k_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0)                                  AS avg_loss_per_return,
    ROUND(COALESCE(AVG(r.resolution_days), 0), 1)                             AS avg_resolution_days
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category
ORDER BY total_loss_k_inr DESC;


-- ─────────────────────────────────────────────────────────────
-- Q3. SUB-CATEGORY DRILLDOWN  ← worst sub-categories per category
-- ANSWERS: Within each category, which exact sub-type is the root cause?
-- EXPECTED: Within F&V: Exotic Veg > Leafy Greens > Fresh Fruits.
--           Within Meat: Fish and Prawns top the list.
-- ACTION  : Dark-store managers focus daily QC on these exact sub-categories.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.category,
    o.sub_category,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1)                          AS loss_k_inr,
    RANK() OVER (
        PARTITION BY o.category
        ORDER BY SUM(o.is_returned) * 1.0 / COUNT(o.order_id) DESC
    )                                                                          AS rank_in_category
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category, o.sub_category
HAVING COUNT(o.order_id) >= 50
ORDER BY o.category, rank_in_category;


-- ─────────────────────────────────────────────────────────────
-- Q4. TOP 25 HIGH-RETURN SKUs  ← the exact products to investigate
-- ANSWERS: Which SKUs have return rates above 20% with meaningful volume?
-- EXPECTED: ~20-25 SKUs, mostly perishables and Budget-tier products.
-- ACTION  : Weekly share with procurement & quality team.
--           Delist SKUs above 30% return rate after supplier review.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.sku_id,
    p.product_name,
    p.brand,
    o.category,
    o.sub_category,
    o.brand_tier,
    p.is_perishable,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1)                          AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.refund_amount), 0), 0)                               AS avg_refund_inr,
    CASE
        WHEN ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 30
            THEN 'DELIST_CANDIDATE'
        WHEN ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 25
            THEN 'URGENT_AUDIT'
        ELSE 'QUALITY_REVIEW'
    END                                                                        AS action
FROM orders o
JOIN  products p ON o.sku_id = p.sku_id
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.sku_id, p.product_name, p.brand, o.category, o.sub_category, o.brand_tier, p.is_perishable
HAVING COUNT(o.order_id) >= 30
   AND ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 20
ORDER BY total_loss_k_inr DESC
LIMIT 25;


-- =============================================================================
-- BLOCK C  ─  DELIVERY SLOT DIMENSION  (Root Cause #2)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q5. RETURN RATE BY DELIVERY SLOT + SLA CORRELATION
-- ANSWERS: Which time windows produce the most returns?
--          Is SLA breach directly linked to returns?
-- EXPECTED: Prime Evening (6–9 PM) has 30% SLA breach and highest return rate.
--           Early Morning has cleanest delivery and lowest returns.
-- ACTION  : Cap Prime Evening order volumes. Add 20% delivery agents 5–9 PM.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.delivery_slot,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.sla_breach)                                                          AS sla_breaches,
    ROUND(SUM(o.sla_breach) * 100.0 / COUNT(o.order_id), 2)                  AS sla_breach_pct,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    -- Return rate specifically when SLA was breached
    ROUND(
        SUM(CASE WHEN o.sla_breach = 1 THEN o.is_returned ELSE 0 END) * 100.0
        / NULLIF(SUM(o.sla_breach), 0), 2)                                    AS return_rate_sla_breached,
    -- Return rate when SLA was met
    ROUND(
        SUM(CASE WHEN o.sla_breach = 0 THEN o.is_returned ELSE 0 END) * 100.0
        / NULLIF(SUM(CASE WHEN o.sla_breach = 0 THEN 1 ELSE 0 END), 0), 2)   AS return_rate_sla_met,
    ROUND(AVG(o.delivery_minutes), 1)                                          AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_slot
ORDER BY return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q6. SLA BREACH vs NO-BREACH  ← statistical proof of the link
-- ANSWERS: How much does a late delivery increase return probability?
-- EXPECTED: Breached orders ~32% return rate vs ~16% for on-time.
--           That is a 2× multiplier — every late delivery costs double.
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE o.sla_breach
        WHEN 1 THEN 'SLA Breached  (Late)'
        ELSE        'SLA Met  (On-Time)'
    END                                                                        AS delivery_status,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1)                                          AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.sla_breach
ORDER BY return_rate_pct DESC;


-- =============================================================================
-- BLOCK D  ─  CUSTOMER SEGMENT  (Root Cause #3)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q7. RETURN RATE BY CUSTOMER TENURE SEGMENT
-- ANSWERS: Do new customers return more? Which segment costs the most?
-- EXPECTED: New (<30 days) return 10+ pct points more than Champions.
--           Champions return least — they know what they are buying.
-- ACTION  : Curate first-3-orders list for new users (no risky perishables).
--           Add quality guarantee badge on app for New segment.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.customer_segment,
    COUNT(DISTINCT o.customer_id)                                              AS unique_customers,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(AVG(o.total_paid), 0)                                                AS avg_order_value_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0)                                  AS avg_loss_per_return,
    -- Most common return reason for this segment
    (SELECT r2.return_reason FROM returns r2
     WHERE r2.customer_segment = o.customer_segment
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1)                AS top_return_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.customer_segment
ORDER BY return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q8. REPEAT RETURNER WATCHLIST  ← customers to contact today
-- ANSWERS: Which individual customers have returned 3+ times?
--          Are some abusing the return policy?
-- EXPECTED: A small group (<2%) causes disproportionate losses.
--           Few-reason + many-returns pattern = policy abuse signal.
-- ACTION  : CX team calls Top 30. Flag accounts with ABUSE tag for review.
-- ─────────────────────────────────────────────────────────────
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    c.age_group,
    c.has_subscription,
    COUNT(r.return_id)                                                         AS total_returns,
    ROUND(
        COUNT(r.return_id) * 100.0
        / (SELECT COUNT(*) FROM orders o2 WHERE o2.customer_id = c.customer_id), 2
    )                                                                          AS personal_return_rate_pct,
    ROUND(SUM(r.total_loss), 0)                                                AS lifetime_loss_caused_inr,
    COUNT(DISTINCT r.return_reason)                                            AS distinct_reasons,
    CASE
        WHEN COUNT(r.return_id) >= 7 AND COUNT(DISTINCT r.return_reason) <= 2
            THEN 'POLICY_ABUSE_REVIEW'
        WHEN COUNT(r.return_id) >= 6
            THEN 'HIGH_RETURNER'
        WHEN COUNT(r.return_id) >= 4
            THEN 'PROACTIVE_OUTREACH'
        ELSE 'MONITOR'
    END                                                                        AS risk_flag
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.segment,
         c.tenure_days, c.age_group, c.has_subscription
HAVING COUNT(r.return_id) >= 3
ORDER BY total_returns DESC, lifetime_loss_caused_inr DESC
LIMIT 30;


-- =============================================================================
-- BLOCK E  ─  CITY DIMENSION  (Root Cause #4)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q9. CITY-LEVEL RETURN HEATMAP
-- ANSWERS: Which cities have worst return rates? What is the top reason per city?
-- EXPECTED: Delhi and Mumbai highest. Bengaluru and Pune lowest.
-- ACTION  : City-specific dark-store ops playbook.
--           Delhi → add agents during Prime Evening.
--           Mumbai → stricter cold-chain for F&V.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.city,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    ROUND(AVG(o.total_paid), 0)                                                AS avg_order_value_inr,
    ROUND(COALESCE(AVG(r.refund_amount), 0), 0)                               AS avg_refund_inr,
    -- Top return category in this city
    (SELECT r2.category FROM returns r2 WHERE r2.city = o.city
     GROUP BY r2.category ORDER BY COUNT(*) DESC LIMIT 1)                     AS top_return_category,
    -- Riskiest slot in this city
    (SELECT o2.delivery_slot FROM orders o2
     WHERE o2.city = o.city AND o2.is_returned = 1
     GROUP BY o2.delivery_slot ORDER BY COUNT(*) DESC LIMIT 1)                AS riskiest_slot
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city
ORDER BY return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q10. CITY × CATEGORY MATRIX  ← feeds Power BI pivot heatmap
-- ANSWERS: In which city-category combination are returns peaking?
-- EXPECTED: Delhi × Fruits & Veg and Mumbai × Meat & Seafood are hottest cells.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.city,
    o.category,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1)                          AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city, o.category
ORDER BY o.city, return_rate_pct DESC;


-- =============================================================================
-- BLOCK F  ─  RETURN REASONS  (Root Cause #5)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q11. RETURN REASON BREAKDOWN  ← volume + financial impact
-- ANSWERS: What exactly are customers complaining about?
-- EXPECTED: "Damaged Product" is #1 by both volume and loss.
--           "Expired or Near-Expiry" is top for perishables.
-- ACTION  : Fix packaging → addresses 28% of all returns.
--           Cold-chain SLA → addresses another 17%.
-- ─────────────────────────────────────────────────────────────
SELECT
    r.return_reason,
    r.return_reason_group,
    COUNT(r.return_id)                                                         AS occurrences,
    ROUND(COUNT(r.return_id) * 100.0 / (SELECT COUNT(*) FROM returns), 2)    AS share_pct,
    ROUND(SUM(r.total_loss) / 1000, 0)                                        AS total_loss_k_inr,
    ROUND(AVG(r.total_loss), 0)                                                AS avg_loss_inr,
    ROUND(AVG(r.resolution_days), 1)                                           AS avg_resolution_days,
    -- Which segment is most affected by this reason?
    (SELECT r2.customer_segment FROM returns r2
     WHERE r2.return_reason = r.return_reason
     GROUP BY r2.customer_segment ORDER BY COUNT(*) DESC LIMIT 1)             AS most_affected_segment,
    -- Which category suffers most from this reason?
    (SELECT r3.category FROM returns r3
     WHERE r3.return_reason = r.return_reason
     GROUP BY r3.category ORDER BY COUNT(*) DESC LIMIT 1)                     AS top_category
FROM returns r
GROUP BY r.return_reason, r.return_reason_group
ORDER BY total_loss_k_inr DESC;


-- ─────────────────────────────────────────────────────────────
-- Q12. RETURN REASONS BY DELIVERY SLOT  ← timing of each failure type
-- ANSWERS: Is "Damaged Product" worse in the Prime Evening slot
--          because riders are rushed?
-- EXPECTED: Prime Evening shows disproportionate Damaged + Wrong Item.
--           Afternoon shows more Wrong Item (picker overwhelm at lunch).
-- ─────────────────────────────────────────────────────────────
SELECT
    r.delivery_slot,
    r.return_reason,
    COUNT(*)                                                                   AS occurrences,
    ROUND(SUM(r.total_loss) / 1000, 1)                                        AS loss_k_inr,
    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (PARTITION BY r.delivery_slot), 2)               AS pct_within_slot
FROM returns r
GROUP BY r.delivery_slot, r.return_reason
ORDER BY r.delivery_slot, occurrences DESC;


-- =============================================================================
-- BLOCK G  ─  TREND ANALYSIS
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q13. MONTHLY RETURN RATE TREND (with MoM change)
-- ANSWERS: Is the return problem getting better or worse?
--          Are there seasonal patterns?
-- EXPECTED: Monsoon months (Jul-Sep) spike due to F&V spoilage.
--           Festival months (Oct-Nov) spike due to Changed Mind returns.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.order_month,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(SUM(o.total_paid) / 1000, 0)                                        AS revenue_k_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS loss_k_inr,
    -- Month-over-month change using window function
    ROUND(
        SUM(o.is_returned) * 100.0 / COUNT(o.order_id)
        - LAG(SUM(o.is_returned) * 100.0 / COUNT(o.order_id))
          OVER (ORDER BY o.order_month), 2
    )                                                                          AS mom_change_pct
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.order_month
ORDER BY o.order_month;


-- ─────────────────────────────────────────────────────────────
-- Q14. DAY-OF-WEEK RETURN PATTERN
-- ANSWERS: Do weekends have more returns due to lower QC staffing?
-- EXPECTED: Saturday and Sunday are 2-3 pct points higher than weekdays.
-- ACTION  : Mandatory QC checks on weekends; no capacity cuts on weekends.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.order_dow                                                                AS day_of_week,
    CASE o.order_dow
        WHEN 'Saturday' THEN 'Weekend'
        WHEN 'Sunday'   THEN 'Weekend'
        ELSE                 'Weekday'
    END                                                                        AS day_type,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.order_dow
ORDER BY return_rate_pct DESC;


-- =============================================================================
-- BLOCK H  ─  CROSS-DIMENSIONAL ANALYSIS
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q15. PERISHABLE vs NON-PERISHABLE × SLOT
-- ANSWERS: Do perishables return more AND is this worse in peak slots?
-- EXPECTED: Perishable + Prime Evening can hit 35%+ return rate.
--           Non-perishable stays below 15% even in worst slots.
-- ─────────────────────────────────────────────────────────────
SELECT
    CASE o.is_perishable WHEN 1 THEN 'Perishable' ELSE 'Non-Perishable' END  AS product_type,
    o.delivery_slot,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1)                          AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.is_perishable, o.delivery_slot
ORDER BY o.is_perishable DESC, return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q16. BRAND TIER ANALYSIS  ← does product quality tier affect returns?
-- ANSWERS: Do Budget-brand products get returned more?
-- EXPECTED: Budget tier 23%, Mid 19%, Premium 16%.
--           Budget customers cite "Quality Not as Expected" most often.
-- ACTION  : Review listing standards for Budget-tier perishable SKUs.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.brand_tier,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(AVG(o.mrp), 0)                                                       AS avg_mrp_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    (SELECT r2.return_reason FROM returns r2
     JOIN orders o2 ON r2.order_id = o2.order_id
     WHERE o2.brand_tier = o.brand_tier
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1)                AS top_return_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.brand_tier
ORDER BY return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q17. DARK STORE PERFORMANCE  ← which warehouses are causing returns?
-- ANSWERS: Are certain dark stores responsible for damaged/wrong orders?
-- EXPECTED: Some stores rank significantly higher — ops issue at specific location.
-- ACTION  : Bottom 5 stores get ops audit + retraining for pickers.
-- ─────────────────────────────────────────────────────────────
SELECT
    o.dark_store_id,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1)                                          AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    -- Top reason for this store
    (SELECT r2.return_reason FROM returns r2
     WHERE r2.dark_store_id = o.dark_store_id
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1)                AS top_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.dark_store_id
HAVING COUNT(o.order_id) >= 500
ORDER BY return_rate_pct DESC
LIMIT 15;


-- =============================================================================
-- BLOCK I  ─  ACTIONABLE INTERVENTION QUERIES
-- =============================================================================

-- ─────────────────────────────────────────────────────────────
-- Q18. SLOT CAPACITY RECOMMENDATION  ← ops team action list
-- ANSWERS: Which slots need operational intervention NOW?
-- ─────────────────────────────────────────────────────────────
SELECT
    delivery_slot,
    COUNT(order_id)                                                            AS order_volume,
    ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2)                     AS return_rate_pct,
    ROUND(AVG(delivery_minutes), 1)                                            AS avg_delivery_mins,
    SUM(sla_breach)                                                            AS sla_breaches,
    CASE
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 27
            THEN 'REDUCE_CAPACITY — Return rate critical, cap new orders'
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 20
            THEN 'ADD_AGENTS — SLA pressure driving returns, hire more riders'
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 14
            THEN 'MONITOR — Watch closely, no immediate action'
        ELSE 'HEALTHY — No action needed'
    END                                                                        AS recommendation
FROM orders
GROUP BY delivery_slot
ORDER BY return_rate_pct DESC;


-- ─────────────────────────────────────────────────────────────
-- Q19. CUSTOMER INTERVENTION PRIORITY LIST  ← CX team daily list
-- ANSWERS: Which customers need proactive outreach to prevent churn?
--          Which ones need education vs which need account review?
-- ─────────────────────────────────────────────────────────────
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    c.age_group,
    c.has_subscription,
    COUNT(r.return_id)                                                         AS return_count,
    ROUND(SUM(r.total_loss), 0)                                                AS loss_caused_inr,
    COUNT(DISTINCT r.return_reason)                                            AS unique_reasons,
    CASE
        WHEN c.tenure_days < 90 AND COUNT(r.return_id) >= 3
            THEN 'ONBOARDING_SUPPORT — New user, send quality education'
        WHEN COUNT(r.return_id) >= 7
            THEN 'ACCOUNT_REVIEW — Check for abuse pattern'
        WHEN COUNT(r.return_id) >= 5
            THEN 'COMPENSATION_OUTREACH — Send voucher, gather feedback'
        ELSE 'STANDARD_FOLLOW_UP'
    END                                                                        AS intervention_type
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.segment,
         c.tenure_days, c.age_group, c.has_subscription
HAVING COUNT(r.return_id) >= 2
ORDER BY loss_caused_inr DESC
LIMIT 50;
