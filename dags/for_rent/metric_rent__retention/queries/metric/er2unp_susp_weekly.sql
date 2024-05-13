WITH
ended_rentals_confirmed AS (
  SELECT 
    fct_or.sk_house_listing,
    (fct_or.sk_house_listing + 1) AS nxt_sk_house_listing,
    dc.sk_contract, 
    dc.country_code,
    DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS dt_ended_rental_confirmed
  FROM 
    dw_retention.fact_owner_retention AS fct_or 
  JOIN 
    dw_rent.dim_contract AS dc 
      ON dc.sk_contract = fct_or.sk_contract
  LEFT JOIN
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
    dc.sk_contract
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
listing_daily_aux AS (
  SELECT
    fhl.sk_house_listing,
    fhl.country_code,
    fhl.ts_status_start,
    IF(fhl.status_history = 'alugado' OR (status_history = 'SUSPENDED' AND fhl.status_change_reason ='RENTED'), NULL, fhl.ts_status_end) AS ts_status_end,
    CASE
        WHEN fhl.status_history IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
        WHEN fhl.status_history IN ('edicao','EDITING','edicaoUsuarioNaoConfirmado','edicaoSemUsuario') THEN 'edicao'
        WHEN fhl.status_history IN ('excluido','OPTED_OUT') THEN 'excluido'
        WHEN fhl.status_history IN ('publicado','PUBLISHED') THEN 'publicado'
        WHEN fhl.status_history = 'alugado' OR (fhl.status_history = 'SUSPENDED' AND fhl.status_change_reason ='RENTED') THEN 'alugado'
        WHEN fhl.status_history IN ('suspenso','SUSPENDED')  THEN 'suspenso'
        WHEN fhl.status_history IS NULL THEN 'aguardando_publicacao'
        ELSE fhl.status_history
    END AS status_history,
    fhl.is_last_status_of_day
  FROM
    dw_rent.fact_house_listing_status AS fhl
  LEFT JOIN 
    contract_signed AS cs 
      ON cs.sk_house_listing = fhl.sk_house_listing
  WHERE
    cs.sk_house_listing IS NULL
    OR (
      cs.sk_house_listing IS NOT NULL 
      AND DATE(fhl.ts_status_start) <= cs.contract_signed_date
    )
),
listings_daily AS (
  SELECT
    dt.date,
    DATE_TRUNC('MONTH',dt.date) AS month,
    DATE_TRUNC('MONTH',DATE(erc.dt_ended_rental_confirmed)) AS listing_start_mth,
    DATE(erc.dt_ended_rental_confirmed) AS listing_start_date,
    DATEDIFF(dt.date, DATE(erc.dt_ended_rental_confirmed)) AS days_since_pub,
    fhl.sk_house_listing,
    fhl.status_history
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
    1,2,3,4,5,6,7
),
listing_status AS (
  SELECT
    sk_house_listing,
    MAX(
      CASE
        WHEN ld.status_history IN ('despublicado','excluido','edicao') AND ld.days_since_pub = 7 THEN 3
        WHEN ld.status_history IN ('suspenso','aguardando_publicacao') AND ld.days_since_pub = 7 THEN 2
        WHEN ld.status_history = 'publicado' AND ld.days_since_pub = 7 THEN 1
        ELSE 0
      END
    ) AS status_1w
  FROM
    listings_daily AS ld
  GROUP BY
    1
),
listing_base AS (
  SELECT
    DATE_TRUNC('MONTH', DATE(erc.dt_ended_rental_confirmed)) AS listing_start_mth,
    DATE(erc.dt_ended_rental_confirmed) AS listing_start_dt,
    erc.nxt_sk_house_listing AS sk_house_listing,
    erc.country_code,
    dhl.is_early_demand,
    CASE
      WHEN dhl.status IS NULL THEN 'nao_relistado'
      WHEN dhl.status IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
      WHEN dhl.status IN ('edicao','EDITING') THEN 'edicao'
      WHEN dhl.status IN ('excluido','OPTED_OUT') THEN 'excluido'
      WHEN dhl.status IN ('publicado','PUBLISHED') THEN 'publicado'
      WHEN dhl.status = 'alugado' OR (dhl.status = 'SUSPENDED' AND dhl.status_reason ='RENTED') THEN 'alugado'
      WHEN dhl.status IN ('suspenso','SUSPENDED')  THEN 'suspenso'
      ELSE dhl.status
    END AS current_status,
    COUNT_IF(
      DISTINCT 
        cs.sk_contract IS NOT NULL 
        AND DATEDIFF(cs.contract_signed_date, DATE(dt_ended_rental_confirmed)) <=7 
    ) AS cs_1w
  FROM 
    ended_rentals_confirmed AS erc
  LEFT JOIN
    dw_rent.dim_house_listing AS dhl 
      ON dhl.sk_house_listing = erc.nxt_sk_house_listing
  LEFT JOIN 
    contract_signed AS cs 
      ON cs.sk_house_listing = erc.nxt_sk_house_listing
  WHERE
    DATE(erc.dt_ended_rental_confirmed) BETWEEN DATE('2022-01-01') AND DATE_ADD(CURRENT_DATE, -1)
  GROUP BY
    1,2,3,4,5,6
),
bd_aux AS (
  SELECT
    lb.listing_start_mth,
    lb.listing_start_dt,
    DATEDIFF(DATE_ADD(CURRENT_DATE,-1), lb.listing_start_dt) AS days_since_pub,
    lb.sk_house_listing,
    lb.current_status,
    CASE
      WHEN lb.cs_1w > 0 THEN 'alugado'
      WHEN ls.status_1w=3 THEN 'despublicado'
      WHEN ls.status_1w=2 THEN 'suspenso'
      WHEN ls.status_1w=1 THEN 'publicado'
      WHEN lb.current_status = 'alugado' THEN 'publicado'
      ELSE lb.current_status
    END AS status_1w
  FROM 
    listing_base AS lb
  LEFT JOIN 
    listing_status AS ls
      ON ls.sk_house_listing = lb.sk_house_listing
  WHERE
    lb.listing_start_dt < CURRENT_DATE
),
bd AS (
  SELECT
    erc.country_code,
    erc.dt_ended_rental_confirmed,
    erc.nxt_sk_house_listing,
    1 AS erc,
    CASE
        WHEN dhl.status IN ('despublicado','UNPUBLISHED') THEN 'despublicado'
        WHEN dhl.status IN ('edicao','EDITING') THEN 'edicao'
        WHEN dhl.status IN ('excluido','OPTED_OUT') THEN 'excluido'
        WHEN dhl.status IN ('publicado','PUBLISHED') THEN 'publicado'
        WHEN dhl.status = 'alugado' OR (dhl.status = 'SUSPENDED' AND dhl.status_reason ='RENTED') THEN 'alugado'
        WHEN dhl.status IN ('suspenso','SUSPENDED')  THEN 'suspenso'
        WHEN dhl.status IS NULL THEN 'aguardando_publicacao'
        ELSE dhl.status
    END AS current_status,
    CASE
        WHEN dhl.rent < 1500 THEN 'LOW'
        WHEN dhl.rent < 2500 THEN 'MEDIUM'
        ELSE 'HIGH'
    END AS rent_segment
  FROM
    ended_rentals_confirmed AS erc
  LEFT JOIN
    dw_rent.dim_house_listing AS dhl
      ON dhl.sk_house_listing = erc.nxt_sk_house_listing
), 
dataset AS (
  SELECT
    DATE_TRUNC('WEEK',bd.dt_ended_rental_confirmed) AS dt_reference_week,
    bd.dt_ended_rental_confirmed,
    bd.country_code,
    bd.rent_segment,
    bd_aux.status_1w,
    SUM(bd.erc) AS erc,
    SUM(IF(bd.dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -7), bd.erc, NULL)) AS erc_matured_1w
  FROM
    bd
  LEFT JOIN
    bd_aux 
      ON bd_aux.sk_house_listing = bd.nxt_sk_house_listing
  GROUP BY
    1,2,3,4,5
)  
SELECT 
  dt_reference_week,
  country_code,
  'OVERALL' AS rent_segment,
  SUM(IF(status_1w IN ('despublicado','suspenso'), erc, 0)) AS unp_susp_1w,
  SUM(IF(
      status_1w IN ('despublicado','suspenso')
      AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -7)
      , erc, 0)) AS unp_susp_matured_1w,
  SUM(erc) AS ended_rentals,
  SUM(erc_matured_1w) AS ended_rentals_matured_1w,
  CAST(SUM(IF(status_1w IN ('despublicado','suspenso'), erc, 0)) AS DOUBLE) / SUM(erc) AS erc2unp_susp_1w,
  CAST(SUM(IF(
      status_1w IN ('despublicado','suspenso')
      AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -7)
      , erc, 0)) AS DOUBLE) / SUM(erc_matured_1w) AS erc2unp_susp_matured_1w
FROM 
  dataset
GROUP BY 
  1,2, 3

UNION ALL

SELECT 
  dt_reference_week,
  country_code,
  rent_segment,
  SUM(IF(status_1w IN ('despublicado','suspenso'), erc, 0)) AS unp_susp_1w,
  SUM(IF(
      status_1w IN ('despublicado','suspenso')
      AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -7)
      , erc, 0)) AS unp_susp_matured_1w,
  SUM(erc) AS ended_rentals,
  SUM(erc_matured_1w) AS ended_rentals_matured_1w,
  CAST(SUM(IF(status_1w IN ('despublicado','suspenso'), erc, 0)) AS DOUBLE) / SUM(erc) AS erc2unp_susp_1w,
  CAST(SUM(IF(
      status_1w IN ('despublicado','suspenso')
      AND dt_ended_rental_confirmed <= DATE_ADD(CURRENT_DATE, -7)
      , erc, 0)) AS DOUBLE) / SUM(erc_matured_1w) AS erc2unp_susp_matured_1w
FROM 
  dataset
GROUP BY 
  1, 2, 3