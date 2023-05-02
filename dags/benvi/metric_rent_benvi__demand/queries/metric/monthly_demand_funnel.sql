WITH tof_demand_funnel AS (
    SELECT 
        COALESCE(tof.city_group, 'Undefined') AS city_group,
        SUM(tof.new_tenant_prospects) AS new_tenant_prospects, 
        SUM(tof.tenant_prospects) AS tenant_prospects,
        DATE(tof.month_start) AS dt_month_started
    FROM 
        dw_datamarts.top_of_funnel_volumes_monthly AS tof
    WHERE
        tof.business_context = 'rent'
        AND tof.month_start >= DATE('2022-06-01')
    GROUP BY 1, 4
),
demand_funnel AS (
    SELECT  
        COALESCE(dr.city_group, 'Undefined') AS city_group,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 1) AS visits_booked,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 2) AS visits_completed,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 3) AS offers_submitted,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 4) AS offers_accepted,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 8) AS credits_approved,
        COUNT(DISTINCT sk_event) FILTER (WHERE sk_event_type = 9) AS contracts_signed,
        DATE(DATE_TRUNC('month', TO_DATE(sk_event_date, 'yyyyMMdd'))) AS dt_month_started
    FROM 
        dw_rent.fact_rent_demand_events AS fr
    LEFT JOIN
        dw_public.dim_region AS dr
            ON dr.sk_region = fr.sk_region
    WHERE
        fr.country_code = 'MX'
        AND fr.sk_event_date >= 20220601
    GROUP BY 1, 8
),
demand_funnel_targets AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        CAST(SUM(NULLIF(REPLACE(visits_booked,',',''), '')) AS FLOAT) AS visits_booked_target,
        CAST(SUM(NULLIF(REPLACE(visits_completed,',',''), '')) AS FLOAT) AS visits_completed_target,
        CAST(SUM(NULLIF(REPLACE(offer_sent,',',''), '')) AS FLOAT) AS offers_submitted_target,
        CAST(SUM(NULLIF(REPLACE(offer_accepted,',',''), '')) AS FLOAT) AS offers_accepted_target,
        CAST(SUM(NULLIF(REPLACE(credit_approved,',',''), '')) AS FLOAT) AS credits_approved_target,
        CAST(SUM(NULLIF(REPLACE(contracts_signed,',',''), '')) AS FLOAT) AS contracts_signed_target,
        DATE(DATE_TRUNC('month', DATE(dt_target))) AS dt_month_started
    FROM 
        datalake_gsheets_clean.mexico_demand_targets_2022
    GROUP BY 1, 8
),
demand_target_costs AS (
    SELECT
        COALESCE(city, 'Undefined') AS city,
        SUM(week_value) AS budget_target,
        DATE(DATE_TRUNC('month', dt_week_started)) AS dt_month_started
    FROM
        datalake_gsheets_clean.mexico_marketing_cost_per_source
    GROUP BY 1, 3
),
demand_actual_costs AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        SUM(cost) AS actual_cost,
        DATE(DATE_TRUNC('MONTH', TO_DATE(id_date, 'yyyyMMdd'))) AS dt_month_started
    FROM
        datalake_mexico_marketing_costs.daily_costs
    GROUP BY 1, 3
),
periods_dimension AS (
    SELECT DISTINCT 
        country_code,
        COALESCE(city_group, 'Undefined') AS city_group,
        dt_month_started
    FROM
        datalake_region.city_groups_per_periods
    WHERE
        country_code = 'MX'
        AND dt_month_started >= DATE('2022-06-01')
)
SELECT 
    dim.country_code,
    dim.city_group,
    tdf.new_tenant_prospects,
    tdf.tenant_prospects,
    df.visits_booked,
    df.visits_completed,
    df.offers_submitted,
    df.offers_accepted,
    df.contracts_signed,
    df.credits_approved,
    dft.visits_booked_target,
    dft.visits_completed_target,
    dft.offers_submitted_target,
    dft.offers_accepted_target,
    dft.credits_approved_target,
    dft.contracts_signed_target,
    dtc.budget_target,
    dac.actual_cost,
    dim.dt_month_started
FROM
    periods_dimension AS dim
LEFT JOIN
    demand_funnel AS df
        ON dim.dt_month_started = df.dt_month_started 
        AND dim.city_group = df.city_group
LEFT JOIN
    demand_funnel_targets AS dft
        ON dim.dt_month_started = dft.dt_month_started 
        AND dim.city_group = dft.city_group   
LEFT JOIN
    demand_target_costs AS dtc
        ON dtc.city = dim.city_group
        AND dtc.dt_month_started = dim.dt_month_started
LEFT JOIN
    demand_actual_costs AS dac
        ON dac.city_group = dim.city_group
        AND dac.dt_month_started = dim.dt_month_started
LEFT JOIN
    tof_demand_funnel AS tdf
        ON df.dt_month_started = tdf.dt_month_started 
        AND df.city_group = tdf.city_group