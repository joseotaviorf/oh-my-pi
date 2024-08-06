SELECT 
    DATE(ts_snapshot) AS dt_reference_day,
    COUNT_IF(is_overdue_stock) AS qtd_overdue_stock,
    COUNT(is_overdue_stock) AS qtd_ongoing_terminations,
    ROUND(100.00 * COUNT_IF(is_overdue_stock)/COUNT(is_overdue_stock), 2) AS percent_overdue_stock
FROM 
    dw_retention.fact_ongoing_terminations_snapshots
GROUP BY 
  1