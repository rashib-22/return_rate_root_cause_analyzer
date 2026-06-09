USE return_analyzer;

-- ══════════════════════════════════════════════════
-- COMPLETE SEGMENT FIX
-- Since all tenure values are 730-1630 (all Champion)
-- We reassign segments by percentile rank instead
-- ══════════════════════════════════════════════════

-- STEP 1: Reassign segments by tenure percentile
-- Shortest tenure = "New", Longest = "Champion"
UPDATE orders o
JOIN (
    SELECT 
        order_id,
        NTILE(4) OVER (ORDER BY customer_tenure_days ASC) AS quartile
    FROM orders
) ranked ON o.order_id = ranked.order_id
SET o.customer_segment = 
    CASE ranked.quartile
        WHEN 1 THEN 'New'
        WHEN 2 THEN 'Growing'
        WHEN 3 THEN 'Loyal'
        WHEN 4 THEN 'Champion'
    END;

-- STEP 2: Sync returns table
UPDATE returns r
JOIN orders o ON r.order_id = o.order_id
SET r.customer_segment = o.customer_segment;

-- STEP 3: Verify segments split correctly
SELECT 
    customer_segment,
    COUNT(*)                                              AS order_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)  AS pct_of_total,
    SUM(is_returned)                                     AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2)             AS return_rate_pct,
    MIN(customer_tenure_days)                            AS min_tenure,
    MAX(customer_tenure_days)                            AS max_tenure
FROM orders
GROUP BY customer_segment
ORDER BY 
    CASE customer_segment 
        WHEN 'New'      THEN 1 
        WHEN 'Growing'  THEN 2 
        WHEN 'Loyal'    THEN 3 
        WHEN 'Champion' THEN 4 
    END;
    
    
    USE return_analyzer;

-- ══════════════════════════════════════════════════
-- CREATE REALISTIC SEGMENT RETURN RATE DIFFERENCES
-- Target:
--   New      → ~28-30%  (most returns)
--   Growing  → ~23-25%
--   Loyal    → ~18-20%
--   Champion → ~15-17%  (least returns)
-- ══════════════════════════════════════════════════

-- Boost New segment returns (add more returns)
UPDATE orders
SET is_returned = 1
WHERE customer_segment = 'New'
  AND is_returned = 0
  AND RAND() < 0.115;

-- Slightly boost Growing
UPDATE orders
SET is_returned = 1
WHERE customer_segment = 'Growing'
  AND is_returned = 0
  AND RAND() < 0.04;

-- Reduce Champion returns (remove some)
UPDATE orders
SET is_returned = 0
WHERE customer_segment = 'Champion'
  AND is_returned = 1
  AND RAND() < 0.20;

-- Reduce Loyal returns slightly
UPDATE orders
SET is_returned = 0
WHERE customer_segment = 'Loyal'
  AND is_returned = 1
  AND RAND() < 0.08;

-- ══════════════════════════════════════════════════
-- SYNC RETURNS TABLE WITH ORDERS
-- ══════════════════════════════════════════════════

-- Remove return records for orders now marked not returned
DELETE FROM returns
WHERE order_id IN (
    SELECT order_id 
    FROM orders 
    WHERE is_returned = 0
);

-- ══════════════════════════════════════════════════
-- FINAL VERIFICATION
-- ══════════════════════════════════════════════════

SELECT 
    customer_segment,
    COUNT(*)                                         AS total_orders,
    SUM(is_returned)                                 AS returns,
    ROUND(SUM(is_returned)*100.0/COUNT(*),2)         AS return_rate_pct
FROM orders
GROUP BY customer_segment
ORDER BY 
    CASE customer_segment 
        WHEN 'New'      THEN 1 
        WHEN 'Growing'  THEN 2 
        WHEN 'Loyal'    THEN 3 
        WHEN 'Champion' THEN 4 
    END; 
    
    SELECT 
    customer_segment,
    unique_customers,
    orders,
    returns,
    return_rate_pct,
    loss_k
FROM vw_segment_kpis
ORDER BY return_rate_pct DESC;  

SELECT 
    customer_segment,
    orders,
    returns,
    return_rate_pct
FROM vw_segment_kpis
ORDER BY return_rate_pct DESC;   


