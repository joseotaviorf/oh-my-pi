WITH
ended_rentals_confirmed AS (
  SELECT 
    (fct_or.sk_house_listing + 1) AS nxt_sk_house_listing,
    dc.sk_contract,
    dc.value_segment,
    fct_or.country_code,
    DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS dt_ended_rental_confirmed
  FROM 
    dw_retention.fact_owner_retention AS fct_or 
  JOIN 
    dw_rent.dim_contract AS dc 
      ON dc.sk_contract = fct_or.sk_contract
  JOIN
    dw_rent.dim_house_listing AS dhl
        ON dhl.sk_house_listing = fct_or.sk_house_listing
  WHERE 
    dc.status = 'Finalizado'
    AND COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment) IS NOT NULL
  QUALIFY 
    ROW_NUMBER() 
        OVER(
            PARTITION BY 
                fct_or.sk_house_listing, 
                DATE_TRUNC('MONTH',DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment))) 
                ORDER BY DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) DESC
        ) = 1
),
contract_signed AS (
  SELECT
    DATE(dc.ts_signature) AS contract_signed_date,
    fct_or.sk_house_listing,
    fct_or.sk_contract AS sk_contract
  FROM 
    dw_retention.fact_owner_retention AS fct_or 
  JOIN 
    dw_rent.dim_contract AS dc 
      ON fct_or.sk_contract = dc.sk_contract
  WHERE
    dc.ts_signature IS NOT NULL
    AND dc.status IN ('Ativo','Finalizado')
    AND dc.ts_signature < CURRENT_DATE
  GROUP BY
    1,2,3
),
listing_base AS (
  SELECT
    DATE(dt_ended_rental_confirmed) AS listing_start_dt,
    erc.nxt_sk_house_listing AS sk_house_listing,
    CASE
        WHEN dhl.status IS NULL THEN 'nao_relistado'
        WHEN dhl.status IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
        WHEN dhl.status IN ('edicao','EDITING') THEN 'edicao'
        WHEN dhl.status IN ('excluido','OPTED_OUT') THEN 'excluido'
        WHEN dhl.status IN ('publicado','PUBLISHED') THEN 'publicado'
        WHEN dhl.status = 'alugado' OR (dhl.status = 'SUSPENDED' AND dhl.status_reason ='RENTED') THEN 'alugado'
        WHEN dhl.status IN ('suspenso','SUSPENDED') THEN 'suspenso'
        ELSE dhl.status
    END AS current_status,
    COUNT(
      DISTINCT(
        IF(
          cs.sk_contract IS NOT NULL
          AND DATEDIFF(cs.contract_signed_date, DATE(dt_ended_rental_confirmed)) <= 28
          , cs.sk_contract
          , NULL
        )
      )
    ) AS cs_4w,
    COUNT(
      DISTINCT(
        IF(
          cs.sk_contract IS NOT NULL
          AND DATEDIFF(cs.contract_signed_date, DATE(dt_ended_rental_confirmed)) <= 84
          , cs.sk_contract
          , NULL
        )
      )
    ) AS cs_12w
  FROM 
    ended_rentals_confirmed AS erc
  LEFT JOIN 
    contract_signed AS cs 
      ON cs.sk_house_listing = erc.nxt_sk_house_listing
  LEFT JOIN 
    dw_rent.dim_house_listing AS dhl 
      ON dhl.sk_house_listing = erc.nxt_sk_house_listing
  WHERE 
    DATE(dt_ended_rental_confirmed) BETWEEN DATE('2022-01-01') AND DATE_ADD(CURRENT_DATE, -1)
  GROUP BY
    1,2,3
),
listing_daily_aux AS (
  SELECT
    fhl.sk_house_listing,
    fhl.ts_status_start,
    IF(
      fhl.status_history = 'alugado' 
      OR (
        status_history = 'SUSPENDED' 
        AND fhl.status_change_reason ='RENTED'
      ) 
      , NULL
      , fhl.ts_status_end
    ) AS ts_status_end,
    CASE
      WHEN fhl.status_history IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
      WHEN fhl.status_history IN ('edicao','EDITING','edicaoUsuarioNaoConfirmado','edicaoSemUsuario') THEN 'edicao'
      WHEN fhl.status_history IN ('excluido','OPTED_OUT') THEN 'excluido'
      WHEN fhl.status_history IN ('publicado','PUBLISHED') THEN 'publicado'
      WHEN fhl.status_history = 'alugado' OR (status_history = 'SUSPENDED' AND fhl.status_change_reason ='RENTED') THEN 'alugado'
      WHEN fhl.status_history IN ('suspenso','SUSPENDED')  THEN 'suspenso'
      WHEN fhl.status_history IS NULL THEN 'aguardando_publicacao'
      ELSE fhl.status_history
    END AS status_history,
    fhl.status_change_reason,
    fhl.is_last_status_of_day
  FROM
    dw_rent.fact_house_listing_status AS fhl
  LEFT JOIN
    contract_signed AS cs
      ON cs.sk_house_listing = fhl.sk_house_listing
  WHERE
    (
      cs.sk_house_listing IS NULL
      OR (cs.sk_house_listing IS NOT NULL AND DATE(ts_status_start) <= cs.contract_signed_date)
    )
),
listings_daily AS (
  SELECT
    DATEDIFF(dt.date, DATE(erc.dt_ended_rental_confirmed)) AS days_since_pub,
    fhl.sk_house_listing,
    fhl.status_history,
    fhl.status_change_reason
  FROM
    listing_daily_aux AS fhl
  INNER JOIN
    ended_rentals_confirmed AS erc 
      ON erc.nxt_sk_house_listing = fhl.sk_house_listing
  INNER JOIN 
    dw_public.dim_date AS dt
      ON fhl.is_last_status_of_day = TRUE
        AND dt.date >= DATE(fhl.ts_status_start)
        AND dt.date < COALESCE(DATE(fhl.ts_status_end), DATE_ADD(CURRENT_DATE,100))
  WHERE
    DATE(fhl.ts_status_start) < CURRENT_DATE
  GROUP BY
    1,2,3,4
),
listing_status AS (
  SELECT
    sk_house_listing,
    MAX(
      CASE
        WHEN ld.status_history IN ('despublicado','excluido','edicao') AND ld.days_since_pub = 28 THEN 3
        WHEN ld.status_history IN ('suspenso','aguardando_publicacao') AND ld.days_since_pub = 28 THEN 2
        WHEN ld.status_history = 'publicado' AND ld.days_since_pub = 28 THEN 1
        ELSE 0
      END
    ) AS status_4w,
    MAX(IF(ld.days_since_pub = 28, ld.status_change_reason, '-')) as status_change_reason_4w,
    MAX(
      CASE
        WHEN ld.status_history IN ('despublicado','excluido','edicao') AND ld.days_since_pub = 84 THEN 3
        WHEN ld.status_history IN ('suspenso','aguardando_publicacao') AND ld.days_since_pub = 84 THEN 2
        WHEN ld.status_history = 'publicado' AND ld.days_since_pub = 84 THEN 1
        ELSE 0
      END
    ) AS status_12w,
    MAX(IF(ld.days_since_pub = 84, ld.status_change_reason, '-')) AS status_change_reason_12w  
  FROM
    listings_daily AS ld
  GROUP BY
    1
),
bd_aux AS (
  SELECT
    lb.sk_house_listing,
    CASE
        WHEN lb.cs_4w > 0 THEN 'alugado'
        WHEN ls.status_4w = 3 THEN 'despublicado'
        WHEN ls.status_4w = 2 THEN 'suspenso'
        WHEN ls.status_4w = 1 THEN 'publicado'
        WHEN lb.current_status = 'alugado' THEN 'publicado'
        ELSE lb.current_status
    END AS status_4w,
    CASE
        WHEN lb.cs_12w > 0 THEN 'alugado'
        WHEN ls.status_12w = 3 THEN 'despublicado'
        WHEN ls.status_12w = 2 THEN 'suspenso'
        WHEN ls.status_12w = 1 THEN 'publicado'
        WHEN lb.current_status = 'alugado' THEN 'publicado'
        ELSE lb.current_status
    END AS status_12w,
    ls.status_change_reason_4w,
    ls.status_change_reason_12w
  FROM 
    listing_base AS lb
  LEFT JOIN
    listing_status AS ls 
      ON ls.sk_house_listing = lb.sk_house_listing
  WHERE
    lb.listing_start_dt < CURRENT_DATE
),
final_base AS (
  SELECT
    DATE_TRUNC('WEEK', erc.dt_ended_rental_confirmed) AS dt_reference_week,
    erc.value_segment,
    erc.country_code,
    COUNT(DISTINCT erc.sk_contract) AS ended_rentals,
    COUNT(DISTINCT 
      IF(
          erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -28)
          , erc.sk_contract
          , NULL
      )
    ) AS ended_rentals_matured_4w,
    COUNT(DISTINCT 
      IF(
          erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -84)
          , erc.sk_contract
          , NULL
      )
    ) AS ended_rentals_matured_12w,
    COUNT_IF(bd_aux.status_4w = 'alugado') AS rerentals_4w,
    COUNT_IF(bd_aux.status_4w = 'alugado' AND erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -28)) rerentals_matured_4w,
    COUNT_IF(bd_aux.status_12w = 'alugado') AS rerentals_12w,
    COUNT_IF(bd_aux.status_12w = 'alugado' AND erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -84)) rerentals_matured_12w,
    COUNT_IF(   
      bd_aux.status_4w IS NULL OR 
      bd_aux.status_4w = 'nao_relistado' OR
      bd_aux.status_4w = 'despublicado' OR
      (
        bd_aux.status_4w = 'suspenso' 
        AND LOWER(bd_aux.status_change_reason_4w) NOT IN ('housereserved','contractdraft') 
      )
    ) AS churn_4w,
    COUNT_IF(   
      (bd_aux.status_4w IS NULL OR 
      bd_aux.status_4w = 'nao_relistado' OR
      bd_aux.status_4w = 'despublicado' OR
      (
        bd_aux.status_4w = 'suspenso' 
        AND LOWER(bd_aux.status_change_reason_4w) NOT IN ('housereserved','contractdraft') 
      ))
      AND erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -28)
    ) AS churn_matured_4w,
    COUNT_IF(   
      bd_aux.status_12w IS NULL OR 
      bd_aux.status_12w = 'nao_relistado' OR
      bd_aux.status_12w = 'despublicado' OR
      (
        bd_aux.status_12w = 'suspenso' 
        AND LOWER(bd_aux.status_change_reason_12w) NOT IN ('housereserved','contractdraft') 
      )
    ) AS churn_12w,
    COUNT_IF(   
      (bd_aux.status_12w IS NULL OR 
      bd_aux.status_12w = 'nao_relistado' OR
      bd_aux.status_12w = 'despublicado' OR
      (
        bd_aux.status_12w = 'suspenso' 
        AND LOWER(bd_aux.status_change_reason_12w) NOT IN ('housereserved','contractdraft') 
      ))
      AND erc.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE(), -84)
    ) AS churn_matured_12w
  FROM 
    ended_rentals_confirmed AS erc
  LEFT JOIN 
    bd_aux 
      ON bd_aux.sk_house_listing = erc.nxt_sk_house_listing
  GROUP BY
    DATE_TRUNC('WEEK',erc.dt_ended_rental_confirmed),
    erc.value_segment,
    erc.country_code
), 
final_dataset AS (
  SELECT  
    dt_reference_week,
    country_code,
    value_segment,
    ended_rentals,
    rerentals_4w,
    rerentals_12w,
    churn_4w,
    churn_12w,
    ended_rentals_matured_4w,
    ended_rentals_matured_12w,
    rerentals_matured_4w,
    rerentals_matured_12w,
    churn_matured_4w,
    churn_matured_12w
  FROM 
    final_base
)
SELECT 
  dt_reference_week,
  country_code,
  'OVERALL' AS value_segment,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals_4w) AS rerentals_4w,
  SUM(churn_4w) AS qtd_churn_4w,
  CAST(SUM(churn_4w) AS DOUBLE) / SUM(ended_rentals)*1.0 AS pct_churn_4w,
  SUM(rerentals_12w) AS rerentals_12w,
  SUM(churn_12w) AS qtd_churn_12w,
  CAST(SUM(churn_12w) AS DOUBLE) / SUM(ended_rentals)*1.0 AS pct_churn_12w,
  SUM(ended_rentals_matured_4w) AS ended_rentals_matured_4w,
  SUM(ended_rentals_matured_12w) AS ended_rentals_matured_12w,
  SUM(rerentals_matured_4w) AS rerentals_matured_4w,
  SUM(churn_matured_4w) AS qtd_churn_matured_4w,
  CAST(SUM(churn_matured_4w) AS DOUBLE) / SUM(ended_rentals_matured_4w)*1.0 AS pct_churn_matured_4w,
  SUM(rerentals_matured_12w) AS rerentals_matured_12w,
  SUM(churn_matured_12w) AS qtd_churn_matured_12w,
  CAST(SUM(churn_matured_12w) AS DOUBLE) / SUM(ended_rentals_matured_12w)*1.0 AS pct_churn_matured_12w
FROM 
  final_dataset
GROUP BY 
  1, 2, 3

UNION ALL

SELECT 
  dt_reference_week,
  country_code,
  value_segment,
  SUM(ended_rentals) AS ended_rentals,
  SUM(rerentals_4w) AS rerentals_4w,
  SUM(churn_4w) AS qtd_churn_4w,
  CAST(SUM(churn_4w) AS DOUBLE) / SUM(ended_rentals)*1.0 AS pct_churn_4w,
  SUM(rerentals_12w) AS rerentals_12w,
  SUM(churn_12w) AS qtd_churn_12w,
  CAST(SUM(churn_12w) AS DOUBLE) / SUM(ended_rentals)*1.0 AS pct_churn_12w,
  SUM(ended_rentals_matured_4w) AS ended_rentals_matured_4w,
  SUM(ended_rentals_matured_12w) AS ended_rentals_matured_12w,
  SUM(rerentals_matured_4w) AS rerentals_matured_4w,
  SUM(churn_matured_4w) AS qtd_churn_matured_4w,
  CAST(SUM(churn_matured_4w) AS DOUBLE) / SUM(ended_rentals_matured_4w)*1.0 AS pct_churn_matured_4w,
  SUM(rerentals_matured_12w) AS rerentals_matured_12w,
  SUM(churn_matured_12w) AS qtd_churn_matured_12w,
  CAST(SUM(churn_matured_12w) AS DOUBLE) / SUM(ended_rentals_matured_12w)*1.0 AS pct_churn_matured_12w
FROM 
  final_dataset
GROUP BY
  1, 2, 3