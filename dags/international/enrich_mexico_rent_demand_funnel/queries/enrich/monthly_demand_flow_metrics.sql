WITH tof_demand_funnel AS (
    SELECT 
        tof.city_group,
        SUM(tof.new_tenant_prospects) AS new_tenant_prospects, 
        SUM(tof.tenant_prospects) AS tenant_prospects,
        DATE(tof.month_start) AS dt_month_started
    FROM 
        dw_datamarts_growth_cross.top_of_funnel_volumes_monthly AS tof
    WHERE
        tof.business_context = 'rent'
        AND tof.month_start >= DATE('2022-06-01')
    GROUP BY 1, 4
),
demand_funnel AS (
    SELECT  
        ref.city_group,
        SUM(ref.visits_booked) AS visits_booked, 
        SUM(ref.offer_submitted) AS offer_submitted,
        SUM(ref.contract_signed) AS contract_signed,
        DATE(DATE_TRUNC('month', ref.date)) AS dt_month_started
    FROM 
        dw_datamarts_for_rent_cross.rental_events_funnel AS ref
    WHERE
        country_code = 'MX'
        AND ref.date >= DATE('2022-06-01')
    GROUP BY 1, 5
),
demand_funnel_targets AS (
    SELECT
        city_group,
        CAST(SUM(NULLIF(REPLACE(visits_booked,',',''), '')) AS FLOAT) AS visits_booked_target,
        CAST(SUM(NULLIF(REPLACE(visits_completed,',',''), '')) AS FLOAT) AS visits_completed_target,
        CAST(SUM(NULLIF(REPLACE(offer_sent,',',''), '')) AS FLOAT) AS offer_submitted_target,
        CAST(SUM(NULLIF(REPLACE(offer_accepted,',',''), '')) AS FLOAT) AS offer_accepted_target,
        CAST(SUM(NULLIF(REPLACE(credit_approved,',',''), '')) AS FLOAT) AS credit_approved_target,
        CAST(SUM(NULLIF(REPLACE(contracts_signed,',',''), '')) AS FLOAT) AS contract_signed_target,
        DATE(DATE_TRUNC('month', DATE(dt_target))) AS dt_month_started
    FROM 
        datalake_gsheets_clean.mexico_demand_targets_2022
    GROUP BY 1, 8
),
demand_target_costs AS (
    SELECT
        city,
        SUM(week_value) AS budget_target,
        DATE(DATE_TRUNC('month', dt_week_started)) AS dt_month_started
    FROM
        datalake_gsheets_clean.mexico_marketing_cost_per_source
    GROUP BY 1, 3
),
demand_actual_costs AS (
    SELECT
        city,
        SUM(week_value) AS actual_cost,
        DATE(DATE_TRUNC('month', dt_week_started)) AS dt_month_started
    FROM
        datalake_gsheets_clean.mexico_demand_marketing_cost_per_source_actual
    GROUP BY 1, 3
),
periods_dimension AS (
    SELECT DISTINCT 
        dt_month_started,
        country_code,
        city_group,
        year
    FROM
        datalake_region.city_groups_per_periods
    WHERE
        country_code = 'MX'
        AND dt_month_started >= DATE('2022-06-01')
)
SELECT 
    dim.country_code,
    COALESCE(dim.city_group, 'Not Mapped') AS city_group,
    tdf.new_tenant_prospects,
    tdf.tenant_prospects,
    df.visits_booked,
    df.offer_submitted,
    df.contract_signed,
    dft.visits_booked_target,
    dft.visits_completed_target,
    dft.offer_submitted_target,
    dft.offer_accepted_target,
    dft.credit_approved_target,
    dft.contract_signed_target,
    dtc.budget_target,
    dac.actual_cost,
    dim.year AS base_year,
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
        ON dac.city = dim.city_group
        AND dac.dt_month_started = dim.dt_month_started
LEFT JOIN
    tof_demand_funnel AS tdf
        ON df.dt_month_started = tdf.dt_month_started 
        AND df.city_group = tdf.city_group