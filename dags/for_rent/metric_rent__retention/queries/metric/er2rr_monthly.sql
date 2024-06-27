WITH
ended_rentals_confirmed AS (
  SELECT
    fct_or.sk_house_listing,
    dc.rental_administrator,
    fct_or.sk_house AS id_house,
    (fct_or.sk_house_listing + 1) AS nxt_sk_house_listing,
    dc.sk_contract,
    dc.rent,
    dc.value_segment,
    dc.country_code,
    dhl.is_exclusive,
    DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS dt_ended_rental_confirmed,
    ROW_NUMBER() OVER(PARTITION BY fct_or.sk_house_listing, DATE_TRUNC('MONTH',DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment))) ORDER BY DATE(coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) DESC) AS rn
  FROM
    dw_retention.fact_owner_retention AS fct_or
  JOIN
    dw_rent.dim_contract AS dc
      ON dc.sk_contract = fct_or.sk_contract
  LEFT JOIN
    dw_rent.dim_house_listing AS dhl
      ON dhl.sk_house_listing = fct_or.sk_house_listing
  WHERE
    dc.status IN ('Finalizado')
    AND COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment) IS NOT NULL
  QUALIFY
    rn = 1
),
contract_signed AS (
  SELECT
    DATE(dc.ts_signature) AS contract_signed_date,
    dc.rental_administrator,
    fct_or.sk_house_listing,
    fct_or.sk_contract AS sk_contract,
    dc.value_segment
  FROM
    dw_retention.fact_owner_retention AS fct_or
  JOIN
    dw_rent.dim_contract AS dc
      ON fct_or.sk_contract = dc.sk_contract
  WHERE
    dc.ts_signature IS NOT NULL
    AND IF(dc.status IN ('Ativo','Finalizado'), TRUE, FALSE)
    AND dc.ts_signature < CURRENT_DATE
  GROUP BY
    1, 2, 3, 4, 5
),
metric_calculations AS (
  SELECT
    CAST(DATE_TRUNC('MONTH',erc.dt_ended_rental_confirmed) AS DATE) AS dt_reference_month,
    erc.country_code,
    erc.value_segment AS category,
    erc.rental_administrator,
    COUNT(DISTINCT erc.sk_house_listing) AS qtd_ended_rental,
    COUNT(DISTINCT cs.sk_contract) AS qtd_rerental,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_4W,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , cs.sk_contract
          , NULL
        )
    ) AS qtd_rerental_matured_4W,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_12W,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , cs.sk_contract
          , NULL
        )
    ) AS qtd_rerental_matured_12W,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 28
        , 1
        , 0
      )
    ) AS qtd_RR_4W,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 28
        AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
        , 1
        , 0
      )
    ) AS qtd_RR_4W_matured,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 84
        , 1
        , 0
      )
    ) AS qtd_RR_12W,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 84
        AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
        , 1
        , 0
      )
    ) AS qtd_RR_12W_matured
  FROM
    ended_rentals_confirmed AS erc
  LEFT JOIN
    contract_signed AS cs
      ON cs.sk_house_listing = erc.nxt_sk_house_listing
  GROUP BY
    1, 2, 3, 4
),
metric_calculations_maturation_4W AS (
  SELECT
    CAST(DATE_TRUNC('MONTH', DATE_ADD(erc.dt_ended_rental_confirmed, 28)) AS DATE) AS dt_reference_month,
    erc.country_code,
    erc.value_segment AS category,
    erc.rental_administrator,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_4W_by_maturation_date,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
          , cs.sk_contract
          , NULL
        )
    ) AS qtd_rerental_matured_4W_by_maturation_date,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 28
        AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -28)
        , 1
        , 0
      )
    ) AS qtd_RR_4W_by_maturation_date
  FROM
    ended_rentals_confirmed AS erc
  LEFT JOIN
    contract_signed AS cs
      ON cs.sk_house_listing = erc.nxt_sk_house_listing
  GROUP BY
    1, 2, 3, 4
),
metric_calculations_maturation_12W AS (
  SELECT
    CAST(DATE_TRUNC('MONTH', DATE_ADD(erc.dt_ended_rental_confirmed, 84)) AS DATE) AS dt_reference_month,
    erc.country_code,
    erc.value_segment AS category,
    erc.rental_administrator,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_12W_by_maturation_date,
    COUNT(DISTINCT
        IF(
          dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
          , cs.sk_contract
          , NULL
        )
    ) AS qtd_rerental_matured_12W_by_maturation_date,
    SUM(
      IF(
        cs.sk_contract IS NOT NULL
              AND DATEDIFF(cs.contract_signed_date, dt_ended_rental_confirmed) <= 84
        AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -84)
        , 1
        , 0
      )
    ) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    ended_rentals_confirmed AS erc
  LEFT JOIN
    contract_signed AS cs
      ON cs.sk_house_listing = erc.nxt_sk_house_listing
  GROUP BY
    1, 2, 3, 4
),
all_calculations AS (
  SELECT
    mc.dt_reference_month,
    'OVERALL' AS category,
    mc.country_code,
    mc.rental_administrator,
    SUM(mc.qtd_ended_rental) AS ended_rentals,
    SUM(mc.qtd_rerental) AS rerentals,
    SUM(mc.qtd_RR_4W) AS rr_4w,
    SUM(mc.qtd_RR_12W) AS rr_12w,
    SUM(mc.qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
    SUM(mc.qtd_rerental_matured_4W) AS rerentals_matured_4W,
    SUM(mc.qtd_RR_4W_matured) AS qtd_RR_4W_matured,
    SUM(mc.qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
    SUM(mc.qtd_rerental_matured_12W) AS rerentals_matured_12W,
    SUM(mc.qtd_RR_12W_matured) AS qtd_RR_12W_matured,
    SUM(mc4w.qtd_ended_rental_matured_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
    SUM(mc4w.qtd_rerental_matured_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
    SUM(mc4w.qtd_RR_4W_by_maturation_date) AS qtd_RR_4W_by_maturation_date,
    SUM(mc12w.qtd_ended_rental_matured_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
    SUM(mc12w.qtd_rerental_matured_12W_by_maturation_date) AS rerentals_12W_by_maturation_date,
    SUM(mc12w.qtd_RR_12W_matured_by_maturation_date) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    metric_calculations AS mc
  JOIN
    metric_calculations_maturation_4W AS mc4w
      ON mc4w.dt_reference_month = mc.dt_reference_month
        AND mc.category = mc4w.category
        AND mc.country_code = mc4w.country_code
        AND mc.rental_administrator = mc4w.rental_administrator
  JOIN
    metric_calculations_maturation_12W AS mc12w
      ON mc12w.dt_reference_month = mc.dt_reference_month
        AND mc12w.category = mc.category
        AND mc12w.country_code = mc.country_code
        AND mc12w.rental_administrator = mc.rental_administrator
  GROUP BY
    1, 2, 3, 4

  UNION

  SELECT
    mc.dt_reference_month,
    mc.category,
    mc.country_code,
    mc.rental_administrator,
    SUM(mc.qtd_ended_rental) AS ended_rentals,
    SUM(mc.qtd_rerental) AS rerentals,
    SUM(mc.qtd_RR_4W) AS rr_4w,
    SUM(mc.qtd_RR_12W) AS rr_12w,
    SUM(mc.qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
    SUM(mc.qtd_rerental_matured_4W) AS rerentals_matured_4W,
    SUM(mc.qtd_RR_4W_matured) AS qtd_RR_4W_matured,
    SUM(mc.qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
    SUM(mc.qtd_rerental_matured_12W) AS rerentals_matured_12W,
    SUM(mc.qtd_RR_12W_matured) AS qtd_RR_12W_matured,
    SUM(mc4w.qtd_ended_rental_matured_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
    SUM(mc4w.qtd_rerental_matured_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
    SUM(mc4w.qtd_RR_4W_by_maturation_date) AS qtd_RR_4W_by_maturation_date,
    SUM(mc12w.qtd_ended_rental_matured_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
    SUM(mc12w.qtd_rerental_matured_12W_by_maturation_date) AS rerentals_12W_by_maturation_date,
    SUM(mc12w.qtd_RR_12W_matured_by_maturation_date) AS qtd_RR_12W_matured_by_maturation_date
  FROM
    metric_calculations AS mc
  JOIN
    metric_calculations_maturation_4W AS mc4w
      ON mc4w.dt_reference_month = mc.dt_reference_month
        AND mc.category = mc4w.category
        AND mc.country_code = mc4w.country_code
        AND mc.rental_administrator = mc4w.rental_administrator
  JOIN
    metric_calculations_maturation_12W AS mc12w
      ON mc12w.dt_reference_month = mc.dt_reference_month
        AND mc12w.category = mc.category
        AND mc12w.country_code = mc.country_code
        AND mc12w.rental_administrator = mc.rental_administrator
  GROUP BY
    1, 2, 3, 4
)

SELECT
  dt_reference_month,
  category,
  country_code,
  'WITH BO' AS administrator,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals) AS rerentals,
  SUM(rr_4w) AS rr_4w,
  SUM(rr_12w) AS rr_12w,
  CAST(SUM(rr_4w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_4W,
  CAST(SUM(rr_12w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_12W,
  SUM(ended_rentals_matured_4W) AS ended_rentals_matured_4W,
  SUM(rerentals_matured_4W) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(ended_rentals_matured_12W) AS ended_rentals_matured_12W,
  SUM(rerentals_matured_12W) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_12W) * 1.00) AS ER2RR_12W_matured,
  SUM(ended_rentals_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
  SUM(rerentals_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
  CAST(SUM(qtd_RR_4W_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_4W_by_maturation_date) * 1.00) AS ER2RR_4W_by_maturation_date,
  SUM(ended_rentals_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
  SUM(rerentals_12W_by_maturation_date) AS rerentals_12W_by_maturation_date,
  CAST(SUM(qtd_RR_12W_matured_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_12W_by_maturation_date) * 1.00) AS ER2RR_12W_by_maturation_date
FROM
  all_calculations
GROUP BY
  1, 2, 3, 4

UNION

SELECT
  dt_reference_month,
  category,
  country_code,
  'WITHOUT BO' AS administrator,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals) AS rerentals,
  SUM(rr_4w) AS rr_4w,
  SUM(rr_12w) AS rr_12w,
  CAST(SUM(rr_4w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_4W,
  CAST(SUM(rr_12w) AS DOUBLE) / (SUM(ended_rentals) * 1.00) AS ER2RR_12W,
  SUM(ended_rentals_matured_4W) AS ended_rentals_matured_4W,
  SUM(rerentals_matured_4W) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(ended_rentals_matured_12W) AS ended_rentals_matured_12W,
  SUM(rerentals_matured_12W) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(ended_rentals_matured_12W) * 1.00) AS ER2RR_12W_matured,
  SUM(ended_rentals_4W_by_maturation_date) AS ended_rentals_4W_by_maturation_date,
  SUM(rerentals_4W_by_maturation_date) AS rerentals_4W_by_maturation_date,
  CAST(SUM(qtd_RR_4W_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_4W_by_maturation_date) * 1.00) AS ER2RR_4W_by_maturation_date,
  SUM(ended_rentals_12W_by_maturation_date) AS ended_rentals_12W_by_maturation_date,
  SUM(rerentals_12W_by_maturation_date) AS rerentals_12W_by_maturation_date,
  CAST(SUM(qtd_RR_12W_matured_by_maturation_date) AS DOUBLE) / (SUM(ended_rentals_12W_by_maturation_date) * 1.00) AS ER2RR_12W_by_maturation_date
FROM
  all_calculations
WHERE
  rental_administrator != 'OWNER'
GROUP BY
  1, 2, 3, 4