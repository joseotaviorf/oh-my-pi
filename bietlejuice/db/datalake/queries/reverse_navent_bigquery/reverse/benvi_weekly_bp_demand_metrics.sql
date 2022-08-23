WITH dimension_period AS (
  SELECT DISTINCT
      year, 
      week_start 
  FROM 
      dw_public.dim_date
  WHERE
    -- Start date 2022-06-01 based on Benvi's launch on Mexico
    date BETWEEN DATE('2022-06-01') AND DATE_ADD(CURRENT_DATE, 30) 
),
dimension_region AS (
  SELECT DISTINCT
      country_name,
      city_group
  FROM 
      dw_public.dim_region
  WHERE
    id_country = 2
),
dimensions AS (
  SELECT *
  FROM 
      dimension_period
  CROSS JOIN 
      dimension_region
),
tof_demand_funnel AS (
SELECT 
    tof.week_start, 
    tof.city_group,
    SUM(tof.new_tenant_prospects) AS new_tenant_prospects, 
    SUM(tof.tenant_prospects) AS tenant_prospects 
FROM 
    dw_datamarts_growth_cross.top_of_funnel_volumes_weekly AS tof
WHERE
    tof.business_context = 'rent' 
GROUP BY 1, 2
),
demand_funnel AS (
SELECT 
    DATE_TRUNC('week', date) AS week_start, 
    city_group,
    SUM(visits_booked) AS visits_booked,
    SUM(visits_completed) AS visits_completed,
    SUM(offer_submitted) AS offer_submitted,
    SUM(offer_approved) AS offer_accepted,
    SUM(credit_approved) AS credit_approved,
    SUM(contract_signed) AS contract_signed
FROM 
    dw_datamarts_for_rent_cross.rental_events_funnel 
GROUP BY 1, 2
),
demand_funnel_targets AS (
SELECT
    DATE_TRUNC('week', DATE(dt_target)) AS week_start,
    city_group,
    CAST(SUM(NULLIF(REPLACE(visits_booked,',',''), '')) AS REAL) AS visits_booked_target,
    CAST(SUM(NULLIF(REPLACE(visits_completed,',',''), '')) AS REAL) AS visits_completed_target,
    CAST(SUM(NULLIF(REPLACE(offer_sent,',',''), '')) AS REAL) AS offer_submitted_target,
    CAST(SUM(NULLIF(REPLACE(offer_accepted,',',''), '')) AS REAL) AS offer_accepted_target,
    CAST(SUM(NULLIF(REPLACE(credit_approved,',',''), '')) AS REAL) AS credit_approved_target,
    CAST(SUM(NULLIF(REPLACE(contracts_signed,',',''), '')) AS REAL) AS contract_signed_target
FROM 
    datalake_gsheets_clean.mexico_demand_targets_2022
GROUP BY 1, 2
),
demand_target_costs AS (
SELECT
    dt_week_started,
    city,
    SUM(week_value) AS budget_target
FROM
    datalake_gsheets_clean.mexico_marketing_cost_per_source
GROUP BY 1, 2
),
demand_actual_costs AS (
SELECT
    dt_week_started,
    city,
    SUM(week_value) AS actual_cost
FROM
    datalake_gsheets_clean.mexico_demand_marketing_cost_per_source_actual
GROUP BY 1, 2
)
SELECT 
    dim.year AS base_year,
    dim.week_start,
    dim.country_name,
    dim.city_group,
    tdf.new_tenant_prospects,
    tdf.tenant_prospects,
    df.visits_booked,
    df.visits_completed,
    df.offer_submitted,
    df.offer_accepted,
    df.credit_approved,
    df.contract_signed,
    CAST(dft.visits_booked_target AS FLOAT) AS visits_booked_target,
    CAST(dft.visits_completed_target AS FLOAT) AS visits_completed_target,
    CAST(dft.offer_submitted_target AS FLOAT) AS offer_submitted_target,
    CAST(dft.offer_accepted_target AS FLOAT) AS offer_accepted_target,
    CAST(dft.credit_approved_target AS FLOAT) AS credit_approved_target,
    CAST(dft.contract_signed_target AS FLOAT) AS contract_signed_target,
    CAST(dtc.budget_target AS FLOAT) AS budget_target,
    CAST(dac.actual_cost AS FLOAT) AS actual_cost,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    dimensions AS dim
LEFT JOIN
    demand_funnel AS df
        ON dim.week_start = df.week_start 
        AND dim.city_group = df.city_group
LEFT JOIN
    demand_funnel_targets AS dft
        ON dim.week_start = dft.week_start 
        AND dim.city_group = dft.city_group  
LEFT JOIN
    demand_target_costs AS dtc
        ON dtc.city = dim.city_group
        AND dtc.dt_week_started = dim.week_start
LEFT JOIN
    demand_actual_costs AS dac
        ON dac.city = dim.city_group
        AND dac.dt_week_started = dim.week_start
LEFT JOIN
    tof_demand_funnel AS tdf
        ON dim.week_start = tdf.week_start 
        AND dim.city_group = tdf.city_group