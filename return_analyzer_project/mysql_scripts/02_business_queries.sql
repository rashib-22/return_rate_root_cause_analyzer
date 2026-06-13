
-- FILE  : 02_business_queries.sql


USE return_analyzer;



SELECT
    FORMAT(COUNT(DISTINCT o.order_id), 0) AS total_orders,
    FORMAT(COUNT(DISTINCT r.return_id), 0) AS total_returns,
    CONCAT(ROUND(COUNT(DISTINCT r.return_id) * 100.0
           / COUNT(DISTINCT o.order_id), 2), '%') AS return_rate,
    CONCAT('₹', FORMAT(ROUND(SUM(o.total_paid) / 1000000, 2), 2), 'M') AS gross_revenue,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.total_loss), 0) / 1000000, 2), 2), 'M') AS total_loss,
    CONCAT(ROUND(COALESCE(SUM(r.total_loss), 0) / SUM(o.total_paid) * 100, 2), '%') AS margin_erosion,
    CONCAT('₹', FORMAT(ROUND(COALESCE(AVG(r.total_loss), 0), 0), 0)) AS avg_loss_per_return,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.refund_amount), 0) / 1000000, 2), 2), 'M)  AS total_refunds,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.reverse_logistics_cost), 0), 0), 0)) AS total_logistics_cost
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id;





--  RETURN RATE BY CATEGORY  


SELECT
    o.category,
    COUNT(o.order_id) AS total_orders,
    SUM(o.is_returned) AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(SUM(o.total_paid) / 1000, 0) AS revenue_k_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0) AS avg_loss_per_return,
    ROUND(COALESCE(AVG(r.resolution_days), 0), 1)  AS avg_resolution_days
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category
ORDER BY total_loss_k_inr DESC;


-- Q3. SUB-CATEGORY 
SELECT
    o.category,
    o.sub_category,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k_inr,
    RANK() OVER (
        PARTITION BY o.category
        ORDER BY SUM(o.is_returned) * 1.0 / COUNT(o.order_id) DESC
    ) AS rank_in_category
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category, o.sub_category
HAVING COUNT(o.order_id) >= 50
ORDER BY o.category, rank_in_category;



-- Q4. HIGH-RETURN SKUs 
SELECT
    o.sku_id,
    p.product_name,
    p.brand,
    o.category,
    o.sub_category,
    o.brand_tier,
    p.is_perishable,
    COUNT(o.order_id) AS total_orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.refund_amount), 0), 0) AS avg_refund_inr,
    CASE
        WHEN ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 30
            THEN 'DELIST_CANDIDATE'
        WHEN ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 25
            THEN 'URGENT_AUDIT'
        ELSE 'QUALITY_REVIEW'
    END AS action
FROM orders o
JOIN  products p ON o.sku_id = p.sku_id
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.sku_id, p.product_name, p.brand, o.category, o.sub_category, o.brand_tier, p.is_perishable
HAVING COUNT(o.order_id) >= 30
   AND ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 20
ORDER BY total_loss_k_inr DESC
LIMIT 25;

-- Q5. RETURN RATE BY DELIVERY SLOT 
SELECT
    o.delivery_slot,
    COUNT(o.order_id) AS total_orders,
    SUM(o.sla_breach) AS sla_breaches,
    ROUND(SUM(o.sla_breach) * 100.0 / COUNT(o.order_id), 2) AS sla_breach_pct,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    -- Return rate specifically when SLA was breached
    ROUND(
        SUM(CASE WHEN o.sla_breach = 1 THEN o.is_returned ELSE 0 END) * 100.0
        / NULLIF(SUM(o.sla_breach), 0), 2) AS return_rate_sla_breached,
    -- Return rate when SLA was met
    ROUND(
        SUM(CASE WHEN o.sla_breach = 0 THEN o.is_returned ELSE 0 END) * 100.0
        / NULLIF(SUM(CASE WHEN o.sla_breach = 0 THEN 1 ELSE 0 END), 0), 2)   AS return_rate_sla_met,
    ROUND(AVG(o.delivery_minutes), 1) AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_slot
ORDER BY return_rate_pct DESC;



-- Q6. SLA BREACH vs NO-BREACH  
SELECT
    CASE o.sla_breach
        WHEN 1 THEN 'SLA Breached  (Late)'
        ELSE        'SLA Met  (On-Time)'
    END AS delivery_status,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1) AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.sla_breach
ORDER BY return_rate_pct DESC;


-- Q7. RETURN RATE BY CUSTOMER TENURE SEGMENT
SELECT
    o.customer_segment,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(AVG(o.total_paid), 0) AS avg_order_value_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0) AS avg_loss_per_return,
    -- Most common return reason for this segment
    (SELECT r2.return_reason FROM returns r2
     WHERE r2.customer_segment = o.customer_segment
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1)  AS top_return_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.customer_segment
ORDER BY return_rate_pct DESC;


-- Q8. REPEAT RETURNER WATCHLIST  
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    c.age_group,
    c.has_subscription,
    COUNT(r.return_id) AS total_returns,
    ROUND(
        COUNT(r.return_id) * 100.0
        / (SELECT COUNT(*) FROM orders o2 WHERE o2.customer_id = c.customer_id), 2) AS personal_return_rate_pct,
    ROUND(SUM(r.total_loss), 0) AS lifetime_loss_caused_inr,
    COUNT(DISTINCT r.return_reason) AS distinct_reasons,
    CASE
        WHEN COUNT(r.return_id) >= 7 AND COUNT(DISTINCT r.return_reason) <= 2
            THEN 'POLICY_ABUSE_REVIEW'
        WHEN COUNT(r.return_id) >= 6
            THEN 'HIGH_RETURNER'
        WHEN COUNT(r.return_id) >= 4
            THEN 'PROACTIVE_OUTREACH'
        ELSE 'MONITOR'
    END AS risk_flag
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.segment,
         c.tenure_days, c.age_group, c.has_subscription
HAVING COUNT(r.return_id) >= 3
ORDER BY total_returns DESC, lifetime_loss_caused_inr DESC
LIMIT 30;



-- Q9. CITY-LEVEL RETURN 
SELECT
    o.city,
    COUNT(o.order_id) AS total_orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr,
    ROUND(AVG(o.total_paid), 0) AS avg_order_value_inr,
    ROUND(COALESCE(AVG(r.refund_amount), 0), 0) AS avg_refund_inr,
    -- Top return category in this city
    (SELECT r2.category FROM returns r2 WHERE r2.city = o.city
     GROUP BY r2.category ORDER BY COUNT(*) DESC LIMIT 1) AS top_return_category,
    -- Riskiest slot in this city
    (SELECT o2.delivery_slot FROM orders o2
     WHERE o2.city = o.city AND o2.is_returned = 1
     GROUP BY o2.delivery_slot ORDER BY COUNT(*) DESC LIMIT 1) AS riskiest_slot
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city
ORDER BY return_rate_pct DESC;



--  In which city-category combination are returns peaking?

SELECT
    o.city,
    o.category,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city, o.category
ORDER BY o.city, return_rate_pct DESC;


-- Q11. RETURN REASON ─
SELECT
    r.return_reason,
    r.return_reason_group,
    COUNT(r.return_id) AS occurrences,
    ROUND(COUNT(r.return_id) * 100.0 / (SELECT COUNT(*) FROM returns), 2) AS share_pct,
    ROUND(SUM(r.total_loss) / 1000, 0) AS total_loss_k_inr,
    ROUND(AVG(r.total_loss), 0) AS avg_loss_inr,
    ROUND(AVG(r.resolution_days), 1) AS avg_resolution_days,
    --  most affected segment
    (SELECT r2.customer_segment FROM returns r2
     WHERE r2.return_reason = r.return_reason
     GROUP BY r2.customer_segment ORDER BY COUNT(*) DESC LIMIT 1) AS most_affected_segment,
    -- category suffers the most
    (SELECT r3.category FROM returns r3
     WHERE r3.return_reason = r.return_reason
     GROUP BY r3.category ORDER BY COUNT(*) DESC LIMIT 1) AS top_category
FROM returns r
GROUP BY r.return_reason, r.return_reason_group
ORDER BY total_loss_k_inr DESC;



-- Q12. RETURN REASONS BY DELIVERY SLOT  
SELECT
    r.delivery_slot,
    r.return_reason,
    COUNT(*) AS occurrences,
    ROUND(SUM(r.total_loss) / 1000, 1) AS loss_k_inr,
    ROUND(
        COUNT(*) * 100.0
        / SUM(COUNT(*)) OVER (PARTITION BY r.delivery_slot), 2) AS pct_within_slot
FROM returns r
GROUP BY r.delivery_slot, r.return_reason
ORDER BY r.delivery_slot, occurrences DESC;


-- Q13. MONTHLY RETURN RATE TREND 
SELECT
    o.order_month,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(SUM(o.total_paid) / 1000, 0) AS revenue_k_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k_inr,
    -- Month-over-month change using window function
    ROUND(
        SUM(o.is_returned) * 100.0 / COUNT(o.order_id)
        - LAG(SUM(o.is_returned) * 100.0 / COUNT(o.order_id))
          OVER (ORDER BY o.order_month), 2
    ) AS mom_change_pct
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.order_month
ORDER BY o.order_month;

-- Q14. DAY-OF-WEEK RETURN
SELECT
    o.order_dow  AS day_of_week,
    CASE o.order_dow
        WHEN 'Saturday' THEN 'Weekend'
        WHEN 'Sunday'   THEN 'Weekend'
        ELSE 'Weekday'
    END AS day_type,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.order_dow
ORDER BY return_rate_pct DESC;



-- Q15. PERISHABLE vs NON-PERISHABLE 
SELECT
    CASE o.is_perishable WHEN 1 THEN 'Perishable' ELSE 'Non-Perishable' END  AS product_type,
    o.delivery_slot,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.is_perishable, o.delivery_slot
ORDER BY o.is_perishable DESC, return_rate_pct DESC;



-- Q16. BRAND TIER ANALYSIS 
SELECT
    o.brand_tier,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(AVG(o.mrp), 0) AS avg_mrp_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr,
    (SELECT r2.return_reason FROM returns r2
     JOIN orders o2 ON r2.order_id = o2.order_id
     WHERE o2.brand_tier = o.brand_tier
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1) AS top_return_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.brand_tier
ORDER BY return_rate_pct DESC;


-- Q17. which warehouses are causing returns?

SELECT
    o.dark_store_id,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1) AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k_inr,
    -- Top reason 
    (SELECT r2.return_reason FROM returns r2
     WHERE r2.dark_store_id = o.dark_store_id
     GROUP BY r2.return_reason ORDER BY COUNT(*) DESC LIMIT 1) AS top_reason
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.dark_store_id
HAVING COUNT(o.order_id) >= 500
ORDER BY return_rate_pct DESC
LIMIT 15;

-- Q18. SLOT CAPACITY RECOMMENDATION 
SELECT
    delivery_slot,
    COUNT(order_id) AS order_volume,
    ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) AS return_rate_pct,
    ROUND(AVG(delivery_minutes), 1) AS avg_delivery_mins,
    SUM(sla_breach) AS sla_breaches,
    CASE
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 27
            THEN 'REDUCE_CAPACITY — Return rate critical, cap new orders'
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 20
            THEN 'ADD_AGENTS — SLA pressure driving returns, hire more riders'
        WHEN ROUND(SUM(is_returned) * 100.0 / COUNT(order_id), 2) > 14
            THEN 'MONITOR — Watch closely, no immediate action'
        ELSE 'HEALTHY — No action needed'
    END AS recommendation
FROM orders
GROUP BY delivery_slot
ORDER BY return_rate_pct DESC;



-- Q19. CUSTOMER INTERVENTION P
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    c.age_group,
    c.has_subscription,
    COUNT(r.return_id) AS return_count,
    ROUND(SUM(r.total_loss), 0) AS loss_caused_inr,
    COUNT(DISTINCT r.return_reason) AS unique_reasons,
    CASE
        WHEN c.tenure_days < 90 AND COUNT(r.return_id) >= 3
            THEN 'ONBOARDING_SUPPORT — New user, send quality education'
        WHEN COUNT(r.return_id) >= 7
            THEN 'ACCOUNT_REVIEW — Check for abuse pattern'
        WHEN COUNT(r.return_id) >= 5
            THEN 'COMPENSATION_OUTREACH — Send voucher, gather feedback'
        ELSE 'STANDARD_FOLLOW_UP'
    END AS intervention_type
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name, c.city, c.segment,
         c.tenure_days, c.age_group, c.has_subscription
HAVING COUNT(r.return_id) >= 2
ORDER BY loss_caused_inr DESC
LIMIT 50;
