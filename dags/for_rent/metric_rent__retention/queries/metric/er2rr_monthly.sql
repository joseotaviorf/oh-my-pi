with
ended_rentals_confirmed AS (
    SELECT 
      fct_or.sk_house_listing,
      dhl.rental_administrator,
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
        AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
        AND COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment) IS NOT NULL
    QUALIFY 
      rn = 1
),
contract_signed AS (
  SELECT
      DATE(dc.ts_signature) AS contract_signed_date,
      DATE_TRUNC('MONTH', dc.ts_signature) AS contract_signed_month,
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
    AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
    AND IF(dc.status IN ('Ativo','Finalizado'), TRUE, FALSE)
    AND dc.ts_signature < CURRENT_DATE
  GROUP BY
    1,2,3,4,5
),
metric_calculations AS (
  SELECT
    DATE_TRUNC('MONTH',erc.dt_ended_rental_confirmed) AS month_ref,
    erc.value_segment AS category,
    COUNT(DISTINCT erc.sk_house_listing) AS qtd_ended_rental,
    COUNT(DISTINCT cs.sk_contract) AS qtd_rerental,
    COUNT(DISTINCT 
      IF(
          dt_ended_rental_confirmed <= DATE_ADD(current_date, -28)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_4W,
    COUNT(DISTINCT 
      IF(
          dt_ended_rental_confirmed <= DATE_ADD(current_date, -28)
          , cs.sk_contract
          , NULL
        )
    ) AS qtd_rerental_matured_4W,
    COUNT(DISTINCT 
      IF(
          dt_ended_rental_confirmed <= DATE_ADD(current_date, -84)
          , erc.sk_house_listing
          , NULL
        )
    ) AS qtd_ended_rental_matured_12W,
    COUNT(DISTINCT 
      IF(
          dt_ended_rental_confirmed <= DATE_ADD(current_date, -84)
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
        AND dt_ended_rental_confirmed <= DATE_ADD(current_date, -28)
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
        AND dt_ended_rental_confirmed <= DATE_ADD(current_date, -84)
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
    1, 2
)
SELECT 
  month_ref,
  'OVERALL' AS category,
  SUM(qtd_ended_rental) AS ended_rentals,
  SUM(qtd_rerental) AS rerentals,
  SUM(qtd_RR_4W) AS rr_4w,
  SUM(qtd_RR_12W) AS rr_12w,
  CAST(SUM(qtd_RR_4W) AS DOUBLE) / (SUM(qtd_ended_rental) * 1.00) AS ER2RR_4W,
  CAST(SUM(qtd_RR_12W) AS DOUBLE) / (SUM(qtd_ended_rental) * 1.00) AS ER2RR_12W,
  SUM(qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
  SUM(qtd_rerental_matured_4W) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(qtd_ended_rental_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
  SUM(qtd_rerental_matured_12W) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(qtd_ended_rental_matured_12W) * 1.00) AS ER2RR_12W_matured
FROM
  metric_calculations
GROUP BY
  1, 2

UNION

SELECT 
  month_ref,
  category,
  SUM(qtd_ended_rental) AS ended_rentals,
  SUM(qtd_rerental) AS rerentals,
  SUM(qtd_RR_4W) AS rr_4w,
  SUM(qtd_RR_12W) AS rr_12w,
  CAST(SUM(qtd_RR_4W) AS DOUBLE) / (SUM(qtd_ended_rental) * 1.00) AS ER2RR_4W,
  CAST(SUM(qtd_RR_12W) AS DOUBLE) / (SUM(qtd_ended_rental) * 1.00) AS ER2RR_12W,
  SUM(qtd_ended_rental_matured_4W) AS ended_rentals_matured_4W,
  SUM(qtd_rerental_matured_4W) AS rerentals_matured_4W,
  CAST(SUM(qtd_RR_4W_matured) AS DOUBLE) / (SUM(qtd_ended_rental_matured_4W) * 1.00) AS ER2RR_4W_matured,
  SUM(qtd_ended_rental_matured_12W) AS ended_rentals_matured_12W,
  SUM(qtd_rerental_matured_12W) AS rerentals_matured_12W,
  CAST(SUM(qtd_RR_12W_matured) AS DOUBLE) / (SUM(qtd_ended_rental_matured_12W) * 1.00) AS ER2RR_12W_matured
FROM
  metric_calculations
GROUP BY
  1, 2