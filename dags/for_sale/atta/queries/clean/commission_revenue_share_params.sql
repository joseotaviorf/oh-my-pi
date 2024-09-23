SELECT
    id AS id_commission,
    PeriodId AS id_period,
    CreatedByUserId AS id_user_created,
    Bank AS bank_code,
    CAST(MinValue AS VARCHAR(96)) AS min_commission_value,
    CAST(MaxValue AS VARCHAR(96)) AS max_commission_value,
    CAST(TotalCommission AS VARCHAR(96)) AS total_commission_value,
    CAST(RevenueShareLeads AS VARCHAR(96)) AS pct_revenue_share_leads,
    CAST(RevenueShareVarejo AS VARCHAR(96)) AS pct_revenue_share_retail,
    Product AS operation_type,
    TO_TIMESTAMP(CreatedAt) AS ts_created
FROM
    datalake_atta_raw.commission_revenue_share_params
