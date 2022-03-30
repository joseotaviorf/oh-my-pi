SELECT
    supply_channel,
    sales_company,
    Group AS group,
    Contexto AS context,
    prospect,
    qualified,
    opportnunities_ AS opportunities,
    first_listing_ AS first_listing,
    CAST(date AS DATE) AS dt_lead_created,
    CAST(week AS DATE) AS dt_week_started,
    CAST(month AS DATE) AS dt_month_started
FROM
    datalake_gsheets_raw.inside_sale_supply_targets