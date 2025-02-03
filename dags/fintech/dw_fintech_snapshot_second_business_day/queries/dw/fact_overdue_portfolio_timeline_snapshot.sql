SELECT
    *,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM
   dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline
WHERE DATE_TRUNC("MONTH", dt_month_end) = DATE_TRUNC("MONTH",DATEADD(MONTH, -1, '{load_start_date}'))
