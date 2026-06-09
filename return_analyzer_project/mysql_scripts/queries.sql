use return_analyzer;
-- for kpis
SELECT
    FORMAT(COUNT(DISTINCT o.order_id), 0)                                     AS total_orders,
    FORMAT(COUNT(DISTINCT r.return_id), 0)                                    AS total_returns,
    CONCAT(ROUND(COUNT(DISTINCT r.return_id) * 100.0
           / COUNT(DISTINCT o.order_id), 2), '%')                             AS return_rate,
    CONCAT('₹', FORMAT(ROUND(SUM(o.total_paid) / 1000000, 2), 2), 'M')       AS gross_revenue,
    CONCAT('₹', FORMAT(ROUND(COALESCE(SUM(r.total_loss), 0) / 1000000, 2), 2), 'M')
                                                                               AS total_loss,
    CONCAT(ROUND(COALESCE(SUM(r.total_loss), 0) / SUM(o.total_paid) * 100, 2), '%')
                                                                               AS margin_erosion
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id;

-- 2) category return rates
SELECT
    o.category,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0)                                  AS avg_loss_per_return
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category
ORDER BY total_loss_k_inr DESC;

-- 3) subcategory 
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

-- 4) top 25 high return SKUs
SELECT
    o.sku_id,
    p.product_name,
    p.brand,
    o.category,
    o.brand_tier,
    p.is_perishable,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1)                          AS total_loss_k_inr,
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
GROUP BY o.sku_id, p.product_name, p.brand,
         o.category, o.brand_tier, p.is_perishable
HAVING COUNT(o.order_id) >= 30
   AND ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) > 20
ORDER BY total_loss_k_inr DESC
LIMIT 25;

-- 5) delievery slot
SELECT
    o.delivery_slot,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.sla_breach)                                                          AS sla_breaches,
    ROUND(SUM(o.sla_breach) * 100.0 / COUNT(o.order_id), 2)                  AS sla_breach_pct,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(SUM(CASE WHEN o.sla_breach = 1 THEN o.is_returned ELSE 0 END) * 100.0
          / NULLIF(SUM(o.sla_breach), 0), 2)                                  AS return_rate_sla_breached,
    ROUND(SUM(CASE WHEN o.sla_breach = 0 THEN o.is_returned ELSE 0 END) * 100.0
          / NULLIF(SUM(CASE WHEN o.sla_breach=0 THEN 1 ELSE 0 END),0),2)     AS return_rate_sla_met,
    ROUND(AVG(o.delivery_minutes), 1)                                          AS avg_delivery_mins
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_slot
ORDER BY return_rate_pct DESC;

-- 6) SLA breach proof
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

-- 7) Customer Segment
SELECT
    o.customer_segment,
    COUNT(DISTINCT o.customer_id)                                              AS unique_customers,
    COUNT(o.order_id)                                                          AS orders,
    SUM(o.is_returned)                                                         AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(AVG(o.total_paid), 0)                                                AS avg_order_value_inr,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.customer_segment
ORDER BY return_rate_pct DESC;

select * from orders limit 100;

-- 8) repeat returner watchlist
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    COUNT(r.return_id)                                                         AS total_returns,
    ROUND(SUM(r.total_loss), 0)                                                AS loss_caused_inr,
    CASE
        WHEN c.tenure_days < 90 AND COUNT(r.return_id) >= 3
            THEN 'ONBOARDING_SUPPORT'
        WHEN COUNT(r.return_id) >= 7
            THEN 'ACCOUNT_REVIEW'
        WHEN COUNT(r.return_id) >= 5
            THEN 'COMPENSATION_OUTREACH'
        ELSE 'STANDARD_MONITOR'
    END                                                                        AS intervention_type
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name, c.city,
         c.segment, c.tenure_days
HAVING COUNT(r.return_id) >= 3
ORDER BY total_returns DESC
LIMIT 30;

-- 9) city heatmap
SELECT
    o.city,
    COUNT(o.order_id)                                                          AS total_orders,
    SUM(o.is_returned)                                                         AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2)                 AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0)                          AS total_loss_k_inr,
    (SELECT r2.category FROM returns r2 WHERE r2.city = o.city
     GROUP BY r2.category ORDER BY COUNT(*) DESC LIMIT 1)                     AS top_return_category,
    (SELECT o2.delivery_slot FROM orders o2
     WHERE o2.city = o.city AND o2.is_returned = 1
     GROUP BY o2.delivery_slot ORDER BY COUNT(*) DESC LIMIT 1)                AS riskiest_slot
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city
ORDER BY return_rate_pct DESC;

-- 10)In which city-category combination are returns peaking

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

-- 11) retuen reason
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

-- 12) return reason - deleivery slot
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

-- 13) monthly return rate 
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

-- 14) weekend day returns
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

-- 15) perishable and  non-perishable products
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

-- 16) brand-tier orders
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

-- 17) dark store performance
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

-- 18) Slot capacity
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

-- 19) customers intervention priority list 
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


-- Q20: Delivery agent performance analysis
-- Which agents have highest return rates?
USE return_analyzer;

SELECT
    o.delivery_agent_id,
    COUNT(o.order_id)                                         AS deliveries,
    SUM(o.is_returned)                                        AS returns,
    ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2)      AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes),1)                          AS avg_delivery_mins,
    ROUND(SUM(o.sla_breach)*100.0/COUNT(o.order_id),2)       AS sla_breach_pct,
    ROUND(COALESCE(SUM(r.total_loss),0)/1000,1)              AS loss_k,
    CASE
        WHEN ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) > 28
            THEN 'PERFORMANCE_REVIEW'
        WHEN ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) > 22
            THEN 'ADDITIONAL_TRAINING'
        ELSE 'GOOD_PERFORMER'
    END AS action      
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_agent_id
HAVING COUNT(o.order_id) >= 100
ORDER BY return_rate_pct DESC
LIMIT 20;





