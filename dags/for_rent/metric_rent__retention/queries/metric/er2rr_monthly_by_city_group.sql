WITH
rent_flow AS (
  SELECT DISTINCT
    de.sk_house_listing,
    de.sk_contract,
    DATE(de.ts_event) AS dt_contract_signed
  FROM
    dw_rent.fact_rent_demand_events AS de
  WHERE
    de.sk_contract <> -1
    AND de.sk_event_type = 9
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY de.sk_house_listing ORDER BY de.ts_event) = 1
),
next_house_listing_with_contract AS (
  SELECT
    fhl.sk_house_listing,
    LEAD(fhl.sk_house_listing) OVER(PARTITION BY dhl.id_house ORDER BY dhl.ts_listing_version_start) AS next_sk_house_listing
  FROM
    dw_rent.fact_house_listings AS fhl
  JOIN
    dw_rent.dim_house_listing AS dhl
      ON fhl.sk_house_listing = dhl.sk_house_listing
  WHERE
    fhl.sk_contract > -1
),
db_terminations AS (
  SELECT DISTINCT
    COALESCE(ct.id_house_listing, rf.sk_house_listing) AS sk_house_listing,
    ct.id_contract AS sk_contract,
    rf_cs.sk_contract AS next_sk_contract,
    dr.city_group,
    dc.country_code,
    dc.value_segment AS category,
    dc.rental_administrator,
    dc.status AS contract_status,
    dc.dt_start AS contract_start_dt,
    DATE(ct.ts_created) AS tr_dt,
    ct.dt_termination AS td_dt,
    dc.dt_ended_rental_confirmed,
    DATE(dhl.ts_publication) AS rl_dt,
    rf_cs.dt_contract_signed,
    dhl.is_early_demand,
    DATE(dhl.ts_early_demand_started) AS dt_early_demand_started
  FROM
    datalake_offboarding.contract_termination AS ct
  LEFT JOIN
    dw_rent.dim_contract AS dc
      ON ct.id_contract = dc.sk_contract
  LEFT JOIN
    rent_flow rf
      ON ct.id_contract = rf.sk_contract
  LEFT JOIN
    next_house_listing_with_contract AS nhl
      ON COALESCE(ct.id_house_listing, rf.sk_house_listing) = nhl.sk_house_listing
  LEFT JOIN
    dw_rent.dim_house_listing AS dhl
      ON nhl.next_sk_house_listing = dhl.sk_house_listing
  LEFT JOIN
    rent_flow AS rf_cs
      ON dhl.sk_house_listing = rf_cs.sk_house_listing
  LEFT JOIN
    dw_public.dim_region AS dr
      ON ct.id_region = dr.sk_region
  WHERE
    ct.ts_created >= DATE('2022-01-01')
    AND ct.status <> 'CANCELED'
    AND dc.rental_administrator NOT IN ('OWNER', 'THIRD_PARTY')
),

metric_calculations AS (
  SELECT
    CAST(DATE_TRUNC('MONTH',db.dt_ended_rental_confirmed) AS DATE) AS dt_reference_month,
    db.country_code,
    db.category,
    db.rental_administrator,
    db.city_group,
    COUNT(DISTINCT db.sk_house_listing) AS qtd_ended_rental,
    COUNT(DISTINCT db.next_sk_contract) AS qtd_rerental,
    COUNT(DISTINCT
        IF(
          db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , db.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_4W,
    COUNT(DISTINCT
        IF(
          db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , db.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_12W,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 28
        , 1
        , 0
      )
    ) AS qtd_RR_4W,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 28
        AND db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
        , 1
        , 0
      )
    ) AS qtd_RR_4W_matured,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 84
        , 1
        , 0
      )
    ) AS qtd_RR_12W,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 84
        AND db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
        , 1
        , 0
      )
    ) AS qtd_RR_12W_matured
  FROM
    db_terminations AS db
  GROUP BY
    ALL
),
metric_calculations_maturation_4W AS (
  SELECT
    CAST(DATE_TRUNC('MONTH', DATE_ADD(db.dt_ended_rental_confirmed, 28)) AS DATE) AS dt_reference_month,
    db.country_code,
    db.category,
    db.rental_administrator,
    db.city_group,
    COUNT(DISTINCT
        IF(
          db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , db.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_4W_by_maturation_date,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 28
        AND db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
        , 1
        , 0
      )
    ) AS qtd_RR_4W_by_maturation_date
  FROM
    db_terminations AS db
  GROUP BY
    ALL
),
metric_calculations_maturation_12W AS (
  SELECT
    CAST(DATE_TRUNC('MONTH', DATE_ADD(db.dt_ended_rental_confirmed, 84)) AS DATE) AS dt_reference_month,
    db.country_code,
    db.category,
    db.rental_administrator,
    db.city_group,
    COUNT(DISTINCT
        IF(
          db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , db.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_12W_by_maturation_date,
    SUM(
      IF(
        db.next_sk_contract IS NOT NULL
        AND DATEDIFF(db.dt_contract_signed, db.dt_ended_rental_confirmed) <= 84
        AND db.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
        , 1
        , 0
      )
    ) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    db_terminations AS db
  GROUP BY
    ALL
),
all_calculations AS (
  SELECT
    mc.dt_reference_month,
    'OVERALL' AS category,
    mc.country_code,
    mc.rental_administrator,
    mc.city_group,
    SUM(mc.qtd_ended_rental) AS ended_rentals,
    SUM(mc.qtd_rerental) AS rerentals,
    SUM(mc.qtd_RR_4W) AS rr_4w,
    SUM(mc.qtd_RR_12W) AS rr_12w,
    SUM(mc.qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
    SUM(mc.qtd_RR_4W_matured) AS qtd_RR_4W_matured,
    SUM(mc.qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
    SUM(mc.qtd_RR_12W_matured) AS qtd_RR_12W_matured,
    SUM(mc4w.qtd_ended_rental_matured_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
    SUM(mc4w.qtd_RR_4W_by_maturation_date) AS qtd_RR_4W_by_maturation_date,
    SUM(mc12w.qtd_ended_rental_matured_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
    SUM(mc12w.qtd_RR_12W_matured_by_maturation_date) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    metric_calculations AS mc
  LEFT JOIN
    metric_calculations_maturation_4W AS mc4w
      ON mc4w.dt_reference_month = mc.dt_reference_month
        AND mc.category = mc4w.category
        AND mc.country_code = mc4w.country_code
        AND mc.rental_administrator = mc4w.rental_administrator
        AND mc.city_group <=> mc4w.city_group
  LEFT JOIN
    metric_calculations_maturation_12W AS mc12w
      ON mc12w.dt_reference_month = mc.dt_reference_month
        AND mc12w.category = mc.category
        AND mc12w.country_code = mc.country_code
        AND mc12w.rental_administrator = mc.rental_administrator
        AND mc.city_group <=> mc12w.city_group
  GROUP BY
    ALL

  UNION

  SELECT
    mc.dt_reference_month,
    mc.category,
    mc.country_code,
    mc.rental_administrator,
    mc.city_group,
    SUM(mc.qtd_ended_rental) AS ended_rentals,
    SUM(mc.qtd_rerental) AS rerentals,
    SUM(mc.qtd_RR_4W) AS rr_4w,
    SUM(mc.qtd_RR_12W) AS rr_12w,
    SUM(mc.qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
    SUM(mc.qtd_RR_4W_matured) AS qtd_RR_4W_matured,
    SUM(mc.qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
    SUM(mc.qtd_RR_12W_matured) AS qtd_RR_12W_matured,
    SUM(mc4w.qtd_ended_rental_matured_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
    SUM(mc4w.qtd_RR_4W_by_maturation_date) AS qtd_RR_4W_by_maturation_date,
    SUM(mc12w.qtd_ended_rental_matured_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
    SUM(mc12w.qtd_RR_12W_matured_by_maturation_date) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    metric_calculations AS mc
  LEFT JOIN
    metric_calculations_maturation_4W AS mc4w
      ON mc4w.dt_reference_month = mc.dt_reference_month
        AND mc.category = mc4w.category
        AND mc.country_code = mc4w.country_code
        AND mc.rental_administrator = mc4w.rental_administrator
        AND mc.city_group <=> mc4w.city_group
  LEFT JOIN
    metric_calculations_maturation_12W AS mc12w
      ON mc12w.dt_reference_month = mc.dt_reference_month
        AND mc12w.category = mc.category
        AND mc12w.country_code = mc.country_code
        AND mc12w.rental_administrator = mc.rental_administrator
        AND mc.city_group <=> mc12w.city_group
  GROUP BY
    ALL
)

SELECT
  dt_reference_month,
  category,
  country_code,
  'WITH BO' AS administrator,
  city_group,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals) AS rerentals,
  SUM(rr_4w) AS rr_4w,
  SUM(rr_12w) AS rr_12w,
  CAST(SUM(rr_4w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_4W,
  CAST(SUM(rr_12w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_12W,
  SUM(ended_rentals_matured_4W) AS ended_rentals_matured_4W,
  SUM(qtd_RR_4W_matured) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(ended_rentals_matured_12W) AS ended_rentals_matured_12W,
  SUM(qtd_RR_12W_matured) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_12W) * 1.00) AS ER2RR_12W_matured,
  SUM(ended_rentals_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
  SUM(qtd_RR_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
  CAST(SUM(qtd_RR_4W_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_4W_by_maturation_date) * 1.00) AS ER2RR_4W_by_maturation_date,
  SUM(ended_rentals_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
  SUM(qtd_RR_12W_matured_by_maturation_date) AS rerentals_12W_by_maturation_date,
  CAST(SUM(qtd_RR_12W_matured_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_12W_by_maturation_date) * 1.00) AS ER2RR_12W_by_maturation_date
FROM
  all_calculations
GROUP BY
  ALL

UNION

SELECT
  dt_reference_month,
  category,
  country_code,
  'WITHOUT BO' AS administrator,
  city_group,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals) AS rerentals,
  SUM(rr_4w) AS rr_4w,
  SUM(rr_12w) AS rr_12w,
  CAST(SUM(rr_4w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_4W,
  CAST(SUM(rr_12w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_12W,
  SUM(ended_rentals_matured_4W) AS ended_rentals_matured_4W,
  SUM(qtd_RR_4W_matured) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(ended_rentals_matured_12W) AS ended_rentals_matured_12W,
  SUM(qtd_RR_12W_matured) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_12W) * 1.00) AS ER2RR_12W_matured,
  SUM(ended_rentals_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
  SUM(qtd_RR_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
  CAST(SUM(qtd_RR_4W_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_4W_by_maturation_date) * 1.00) AS ER2RR_4W_by_maturation_date,
  SUM(ended_rentals_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
  SUM(qtd_RR_12W_matured_by_maturation_date) AS rerentals_12W_by_maturation_date,
  CAST(SUM(qtd_RR_12W_matured_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_12W_by_maturation_date) * 1.00) AS ER2RR_12W_by_maturation_date
FROM
  all_calculations
WHERE
  rental_administrator != 'OWNER'
GROUP BY
  ALL
