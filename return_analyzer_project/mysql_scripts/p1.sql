USE return_analyzer;

-- Quick check all views work
SELECT 'vw_category_kpis'   AS view_name, COUNT(*) AS `rows` FROM vw_category_kpis
UNION ALL
SELECT 'vw_city_kpis',                    COUNT(*) FROM vw_city_kpis
UNION ALL
SELECT 'vw_monthly_trend',                COUNT(*) FROM vw_monthly_trend
UNION ALL
SELECT 'vw_return_fact',                  COUNT(*) FROM vw_return_fact
UNION ALL
SELECT 'vw_segment_kpis',                 COUNT(*) FROM vw_segment_kpis
UNION ALL
SELECT 'vw_sku_risk',                     COUNT(*) FROM vw_sku_risk
UNION ALL
SELECT 'vw_slot_kpis',                    COUNT(*) FROM vw_slot_kpis;