
USE return_analyzer;

-- VIEW 1: vw_return_fact  

DROP VIEW IF EXISTS vw_return_fact;
CREATE VIEW vw_return_fact AS
SELECT
    r.return_id,
    r.order_id,
    o.order_date,
    o.order_month,
    o.order_quarter,
    o.order_year,
    o.order_dow,
    CASE o.is_weekend WHEN 1 THEN 'Weekend' ELSE 'Weekday' END AS day_type,
    o.city,
    o.category,
    o.sub_category,
    o.brand_tier,
    o.sku_id,
    p.product_name,
    p.brand,
    p.is_perishable,
    p.shelf_life_days,
    o.delivery_slot,
    o.sla_breach,
    CASE o.sla_breach WHEN 1 THEN 'SLA Breached' ELSE 'SLA Met' END  AS sla_status,
    o.delivery_minutes,
    o.quantity,
    o.mrp,
    o.discount_amount,
    o.discount_pct,
    o.total_paid,
    o.payment_method,
    o.order_source,
    o.dark_store_id,
    o.delivery_agent_id,
    o.customer_segment,
    c.tenure_days,
    c.age_group,
    c.gender,
    c.has_subscription,
    c.referral_source,
    r.return_date,
    r.return_month,
    r.days_to_return,
    r.return_reason,
    r.return_reason_group,
    r.refund_amount,
    r.reverse_logistics_cost,
    r.total_loss,
    r.resolution_days,
    r.refund_mode,
    ROUND(r.total_loss / NULLIF(o.total_paid, 0) * 100, 2)  AS loss_pct_of_order
FROM returns r
JOIN orders o ON r.order_id = o.order_id
JOIN products p ON o.sku_id = p.sku_id
JOIN customers c ON o.customer_id = c.customer_id;



-- VIEW 2: vw_category_kpis  

DROP VIEW IF EXISTS vw_category_kpis;
CREATE VIEW vw_category_kpis AS
SELECT
    o.category,
    COUNT(o.order_id) AS total_orders,
    SUM(o.is_returned) AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(SUM(o.total_paid) / 1000, 0) AS revenue_k,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k,
    ROUND(COALESCE(AVG(r.total_loss), 0), 0) AS avg_loss
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.category;

-- VIEW 3: vw_city_kpis  

DROP VIEW IF EXISTS vw_city_kpis;
CREATE VIEW vw_city_kpis AS
SELECT
    o.city,
    COUNT(o.order_id) AS total_orders,
    SUM(o.is_returned) AS total_returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS total_loss_k
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city;

-- VIEW 4: vw_monthly_trend  

DROP VIEW IF EXISTS vw_monthly_trend;
CREATE VIEW vw_monthly_trend AS
SELECT
    o.order_month,
    o.order_year,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.order_month, o.order_year
ORDER BY o.order_month;


-- VIEW 5: vw_slot_kpis  

DROP VIEW IF EXISTS vw_slot_kpis;
CREATE VIEW vw_slot_kpis AS
SELECT
    o.delivery_slot,
    COUNT(o.order_id) AS orders,
    SUM(o.sla_breach) AS sla_breaches,
    ROUND(SUM(o.sla_breach) * 100.0 / COUNT(o.order_id), 2) AS breach_pct,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(AVG(o.delivery_minutes), 1) AS avg_delivery_mins,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.delivery_slot;

-- VIEW 6: vw_segment_kpis  

DROP VIEW IF EXISTS vw_segment_kpis;
CREATE VIEW vw_segment_kpis AS
SELECT
    o.customer_segment,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.customer_segment;

-- VIEW 7: vw_sku_risk  

DROP VIEW IF EXISTS vw_sku_risk;
CREATE VIEW vw_sku_risk AS
SELECT
    o.sku_id,
    p.product_name,
    p.brand,
    o.category,
    o.sub_category,
    o.brand_tier,
    p.is_perishable,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k
FROM orders o
JOIN products p ON o.sku_id = p.sku_id
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.sku_id, p.product_name, p.brand, o.category,
         o.sub_category, o.brand_tier, p.is_perishable
HAVING COUNT(o.order_id) >= 15;

-- STORED PROCEDURES

-- SP 1: Filter by city
-- USAGE : CALL sp_city_analysis('Mumbai');

DROP PROCEDURE IF EXISTS sp_city_analysis;
DELIMITER $$
CREATE PROCEDURE sp_city_analysis(IN p_city VARCHAR(30))
BEGIN
    SELECT
        o.category,
        o.delivery_slot,
        o.customer_segment,
        COUNT(o.order_id) AS orders,
        SUM(o.is_returned) AS returns,
        ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
        ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k
    FROM orders o
    LEFT JOIN returns r ON o.order_id = r.order_id
    WHERE o.city = p_city
    GROUP BY o.category, o.delivery_slot, o.customer_segment
    ORDER BY return_rate_pct DESC;
END$$
DELIMITER ;

-- SP 2: Filter returns by date range
-- USAGE : CALL sp_trend_by_period('2023-07-01', '2023-12-31');

DROP PROCEDURE IF EXISTS sp_trend_by_period;
DELIMITER $$
CREATE PROCEDURE sp_trend_by_period(IN p_start DATE, IN p_end DATE)
BEGIN
    SELECT
        o.order_month,
        COUNT(o.order_id) AS orders,
        SUM(o.is_returned) AS returns,
        ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
        ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 0) AS loss_k
    FROM orders o
    LEFT JOIN returns r ON o.order_id = r.order_id
    WHERE o.order_date BETWEEN p_start AND p_end
    GROUP BY o.order_month
    ORDER BY o.order_month;
END$$
DELIMITER ;

-- SP 3: High-risk SKUs for a given category
-- USAGE : CALL sp_risky_skus('Fruits & Vegetables', 20);

DROP PROCEDURE IF EXISTS sp_risky_skus;
DELIMITER $$
CREATE PROCEDURE sp_risky_skus(IN p_category VARCHAR(60), IN p_min_return_pct DECIMAL(5,2))
BEGIN
    SELECT
        o.sku_id,
        p.product_name,
        o.sub_category,
        COUNT(o.order_id) AS orders,
        SUM(o.is_returned) AS returns,
        ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) AS return_rate_pct,
        ROUND(COALESCE(SUM(r.total_loss), 0) / 1000, 1) AS loss_k
    FROM orders o
    JOIN products p ON o.sku_id = p.sku_id
    LEFT JOIN returns r ON o.order_id = r.order_id
    WHERE o.category = p_category
    GROUP BY o.sku_id, p.product_name, o.sub_category
    HAVING COUNT(o.order_id) >= 15
       AND ROUND(SUM(o.is_returned) * 100.0 / COUNT(o.order_id), 2) >= p_min_return_pct
    ORDER BY loss_k DESC;
END$$
DELIMITER ;

SELECT 'Views and Procedures created successfully' AS status;
SHOW FULL TABLES WHERE Table_type = 'VIEW'; 

DROP VIEW IF EXISTS vw_city_category_heatmap;
CREATE VIEW vw_city_category_heatmap AS
SELECT 
    o.city,
    o.category,
    COUNT(o.order_id) AS orders,
    SUM(o.is_returned) AS returns,
    ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS return_rate_pct,
    ROUND(COALESCE(SUM(r.total_loss),0)/1000,1) AS loss_k
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id
GROUP BY o.city, o.category;



DROP VIEW IF EXISTS vw_repeat_returners;
CREATE VIEW vw_repeat_returners AS
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    COUNT(r.return_id) AS total_returns,
    ROUND(SUM(r.total_loss),0) AS loss_caused,
    CASE
        WHEN c.tenure_days < 90 
             AND COUNT(r.return_id) >= 3
            THEN 'ONBOARDING SUPPORT'
        WHEN COUNT(r.return_id) >= 7
            THEN 'ACCOUNT REVIEW'
        WHEN COUNT(r.return_id) >= 5
            THEN 'SEND VOUCHER'
        ELSE 'MONITOR'
    END AS intervention_type
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name,
         c.city, c.segment, c.tenure_days
HAVING COUNT(r.return_id) >= 3
ORDER BY total_returns DESC;


DROP VIEW IF EXISTS vw_repeat_returners;
CREATE VIEW vw_repeat_returners AS
SELECT
    c.customer_id,
    c.full_name,
    c.city,
    c.segment,
    c.tenure_days,
    COUNT(r.return_id) AS total_returns,
    ROUND(SUM(r.total_loss), 0) AS loss_caused,
    COUNT(DISTINCT r.return_reason) AS distinct_reasons,
    CASE
        WHEN c.segment = 'New'
             AND COUNT(r.return_id) >= 3
            THEN 'ONBOARDING SUPPORT'
        WHEN COUNT(r.return_id) >= 7
            THEN 'ACCOUNT REVIEW'
        WHEN COUNT(r.return_id) >= 5
            THEN 'SEND VOUCHER'
        ELSE 'MONITOR'
    END  AS intervention_type
FROM customers c
JOIN returns r ON c.customer_id = r.customer_id
GROUP BY c.customer_id, c.full_name,
         c.city, c.segment, c.tenure_days
HAVING COUNT(r.return_id) >= 3
ORDER BY total_returns DESC;  


USE return_analyzer;

DROP VIEW IF EXISTS vw_orders_fact;
CREATE VIEW vw_orders_fact AS
SELECT
    o.order_id,
    o.customer_id,
    o.sku_id,
    o.category,
    o.sub_category,
    o.brand_tier,
    o.city,
    o.order_date,
    o.order_month,
    o.order_quarter,
    o.order_year,
    o.order_dow,
    o.is_weekend,
    o.delivery_slot,
    o.total_paid,
    o.sla_breach,
    o.delivery_minutes,
    o.customer_segment,
    o.is_returned,
    o.is_perishable,
    COALESCE(r.total_loss, 0)  AS total_loss,
    COALESCE(r.return_reason, 'N/A') AS return_reason,
    COALESCE(r.refund_amount, 0) AS refund_amount
FROM orders o
LEFT JOIN returns r ON o.order_id = r.order_id;

-- Verify
SELECT 
    COUNT(*) AS total_rows,
    SUM(is_returned) AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2) AS return_rate
FROM vw_orders_fact;   

SELECT 
    category,
    COUNT(*) AS total_orders,
    SUM(is_returned) AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2) AS return_rate
FROM vw_orders_fact
WHERE category = 'Dairy & Eggs'
GROUP BY category;  

SELECT 
    order_month, category,
    COUNT(*) AS orders,
    SUM(is_returned) AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2) AS return_rate_pct
  FROM orders
  GROUP BY order_month, category;   
  
  DROP VIEW IF EXISTS vw_category_monthly_trend;
  CREATE VIEW vw_category_monthly_trend AS
  SELECT
      o.order_month,
      o.category,
      o.city,
      COUNT(o.order_id) AS orders,
      SUM(o.is_returned)  AS returns,
      ROUND(SUM(o.is_returned)*100.0/COUNT(o.order_id),2) AS return_rate_pct,
      ROUND(COALESCE(SUM(r.total_loss),0)/1000,1) AS loss_k
  FROM orders o
  LEFT JOIN returns r ON o.order_id = r.order_id
  GROUP BY o.order_month, o.category, o.city;
