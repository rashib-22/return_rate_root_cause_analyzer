USE return_analyzer;

-- Drop and recreate vw_slot_kpis cleanly
DROP VIEW IF EXISTS vw_slot_kpis;

CREATE VIEW vw_slot_kpis AS
SELECT
    o.delivery_slot,
    COUNT(o.order_id) AS orders,
    SUM(o.sla_breach) AS sla_breaches,
    ROUND(SUM(o.sla_breach)*100.0 / COUNT(o.order_id), 2) AS breach_pct,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned)*100.0 / COUNT(o.order_id), 2)   AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1) AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k,
    CASE
        WHEN ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) > 25
            THEN 'REDUCE CAPACITY'
        WHEN ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) > 18
            THEN 'ADD AGENTS'
        WHEN ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) > 14
            THEN 'MONITOR'
        ELSE 'HEALTHY'
    END AS recommendations
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_slot;

-- Verify it works
SELECT * FROM vw_slot_kpis;  

SELECT 
    segment,
    COUNT(*) AS customers,
    SUM(total_returns) AS total_returns,
    AVG(loss_caused) AS avg_loss,
    intervention_type,
    COUNT(*) AS count_per_action
FROM vw_repeat_returners
GROUP BY segment, intervention_type
ORDER BY 
    CASE segment
        WHEN 'New'      THEN 1
        WHEN 'Growing'  THEN 2
        WHEN 'Loyal'    THEN 3
        WHEN 'Champion' THEN 4
    END;  
