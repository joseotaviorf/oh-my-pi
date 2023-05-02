WITH tof_demand_funnel AS (
    SELECT 
        COALESCE(tof.city_group, 'Undefined') AS city_group,
        SUM(tof.new_tenant_prospects) AS new_tenant_prospects, 
        SUM(tof.tenant_prospects) AS tenant_prospects,
        DATE(tof.week_start) AS dt_week_started
    FROM 
        dw_datamarts.top_of_funnel_volumes_weekly AS tof
    WHERE
        tof.business_context = 'rent'
        AND DATE(tof.week_start) >= DATE('2022-05-30') -- Mexico's launch was on July 1st, but the week started on March 30th. 
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
        DATE(DATE_TRUNC('week', TO_DATE(STRING(sk_event_date), 'yyyyMMdd'))) AS dt_week_started
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
        COALESCE(mdt.city_group, 'Undefined') AS city_group,
        CAST(SUM(NULLIF(REPLACE(mdt.visits_booked,',',''), '')) AS FLOAT) AS visits_booked_target,
        CAST(SUM(NULLIF(REPLACE(mdt.visits_completed,',',''), '')) AS FLOAT) AS visits_completed_target,
        CAST(SUM(NULLIF(REPLACE(mdt.offer_sent,',',''), '')) AS FLOAT) AS offers_submitted_target,
        CAST(SUM(NULLIF(REPLACE(mdt.offer_accepted,',',''), '')) AS FLOAT) AS offers_accepted_target,
        CAST(SUM(NULLIF(REPLACE(mdt.credit_approved,',',''), '')) AS FLOAT) AS credits_approved_target,
        CAST(SUM(NULLIF(REPLACE(mdt.contracts_signed,',',''), '')) AS FLOAT) AS contracts_signed_target,
        DATE(DATE_TRUNC('week', DATE(mdt.dt_target))) AS dt_week_started
    FROM 
        datalake_gsheets_clean.mexico_demand_targets_2022 AS mdt
    GROUP BY 1, 8
),
demand_target_costs AS (
    SELECT
        COALESCE(mmc.city, 'Undefined') AS city,
        SUM(mmc.week_value) AS budget_target,
        mmc.dt_week_started
    FROM
        datalake_gsheets_clean.mexico_marketing_cost_per_source AS mmc
    GROUP BY 1, 3
),
demand_actual_costs AS (
    SELECT
        COALESCE(city_group, 'Undefined') AS city_group,
        SUM(cost) AS actual_cost,
        DATE(DATE_TRUNC('WEEK', TO_DATE(STRING(id_date), 'yyyyMMdd'))) AS dt_week_started
    FROM
        datalake_mexico_marketing_costs.daily_costs
    GROUP BY 1, 3
),
periods_dimension AS (
    SELECT DISTINCT 
        country_code,
        COALESCE(city_group, 'Undefined') AS city_group,
        dt_week_started
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
    df.credits_approved,
    df.contracts_signed,
    dft.visits_booked_target,
    dft.visits_completed_target,
    dft.offers_submitted_target,
    dft.offers_accepted_target,
    dft.credits_approved_target,
    dft.contracts_signed_target,
    dtc.budget_target,
    dac.actual_cost,
    dim.dt_week_started
FROM
    periods_dimension AS dim
LEFT JOIN
    demand_funnel AS df
        ON dim.dt_week_started = df.dt_week_started 
        AND dim.city_group = df.city_group
LEFT JOIN
    demand_funnel_targets AS dft
        ON dim.dt_week_started = dft.dt_week_started 
        AND dim.city_group = dft.city_group  
LEFT JOIN
    demand_target_costs AS dtc
        ON dtc.city = dim.city_group
        AND dtc.dt_week_started = dim.dt_week_started
LEFT JOIN
    demand_actual_costs AS dac
        ON dac.city_group = dim.city_group
        AND dac.dt_week_started = dim.dt_week_started
LEFT JOIN
    tof_demand_funnel AS tdf
        ON dim.dt_week_started = tdf.dt_week_started 
        AND dim.city_group = tdf.city_group