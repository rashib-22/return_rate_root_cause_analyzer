UPDATE customers c
JOIN (
    SELECT 
        customer_id,
        NTILE(4) OVER (ORDER BY tenure_days ASC) AS quartile
    FROM customers
) ranked ON c.customer_id = ranked.customer_id
SET c.segment = 
    CASE ranked.quartile
        WHEN 1 THEN 'New'
        WHEN 2 THEN 'Growing'
        WHEN 3 THEN 'Loyal'
        WHEN 4 THEN 'Champion'
    END; 
    
SELECT segment, COUNT(*) AS customers
FROM customers
GROUP BY segment
ORDER BY CASE segment 
    WHEN 'New' THEN 1 WHEN 'Growing' THEN 2 
    WHEN 'Loyal' THEN 3 WHEN 'Champion' THEN 4 END;  
    
SELECT 
    segment,
    intervention_type,
    COUNT(*) AS customers
FROM vw_repeat_returners
GROUP BY segment, intervention_type
ORDER BY CASE segment 
    WHEN 'New' THEN 1 WHEN 'Growing' THEN 2 
    WHEN 'Loyal' THEN 3 WHEN 'Champion' THEN 4 END;  
    
    
SELECT 'vw_category_kpis'    AS view_name, COUNT(*) AS `rows` FROM vw_category_kpis
UNION ALL SELECT 'vw_city_kpis',            COUNT(*) FROM vw_city_kpis
UNION ALL SELECT 'vw_monthly_trend',        COUNT(*) FROM vw_monthly_trend
UNION ALL SELECT 'vw_return_fact',          COUNT(*) FROM vw_return_fact
UNION ALL SELECT 'vw_segment_kpis',         COUNT(*) FROM vw_segment_kpis
UNION ALL SELECT 'vw_sku_risk',             COUNT(*) FROM vw_sku_risk
UNION ALL SELECT 'vw_slot_kpis',            COUNT(*) FROM vw_slot_kpis
UNION ALL SELECT 'vw_repeat_returners',     COUNT(*) FROM vw_repeat_returners; 

USE return_analyzer;

-- Check total revenue from ALL orders
SELECT 
    ROUND(SUM(total_paid), 0)        AS total_revenue,
    ROUND(SUM(total_loss), 0)        AS total_loss,
    ROUND(SUM(total_loss) / 
          SUM(total_paid) * 100, 2)  AS correct_margin_erosion
FROM (
    SELECT o.total_paid, 
           COALESCE(r.total_loss, 0) AS total_loss
    FROM orders o
    LEFT JOIN returns r ON o.order_id = r.order_id
) combined; 

USE return_analyzer;

SELECT 
    COUNT(CASE WHEN return_rate_pct >= 20 
               AND orders >= 30 THEN 1 END) AS high_risk_20plus,
    COUNT(CASE WHEN return_rate_pct >= 25 
               AND orders >= 30 THEN 1 END) AS high_risk_25plus,
    COUNT(CASE WHEN return_rate_pct >= 30 
               AND orders >= 30 THEN 1 END) AS delist_30plus,
    COUNT(CASE WHEN return_rate_pct >= 35 
               AND orders >= 30 THEN 1 END) AS delist_35plus
FROM vw_sku_risk;  

USE return_analyzer;

-- Check filtered return rate for Bengaluru
SELECT 
    city,
    COUNT(*) AS total_orders,
    SUM(is_returned) AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2) AS return_rate
FROM orders
GROUP BY city
ORDER BY return_rate DESC;  

SELECT is_returned, COUNT(*)
FROM vw_orders_fact
GROUP BY is_returned;  
