SELECT
    id AS id_commission,
    PeriodId AS id_period,
    CreatedByUserId AS id_user_created,
    Bank AS bank_code,
    MinValue AS min_commission_value,
    MaxValue AS max_commission_value,
    TotalCommission AS total_commission_value,
    RevenueShareLeads AS pct_revenue_share_leads,
    RevenueShareVarejo AS pct_revenue_share_retail,
    Product AS operation_type,
    TO_TIMESTAMP(CreatedAt) AS ts_created
FROM
    datalake_atta_test_raw.commission_revenue_share_params
