WITH
ended_rentals_requested AS ( 
    SELECT 
    	fct_or.sk_house_listing,
    	fct_or.sk_house AS id_house,
    	(fct_or.sk_house_listing + 1) AS nxt_sk_house_listing,
    	dc.sk_contract, 
      dc.country_code,
    	ct.ts_created AS termination_request_date,
    	ct.dt_termination AS termination_date,
    	dc.value_segment,
    	DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS dt_ended_rental_confirmed,
    	ROW_NUMBER() OVER(PARTITION BY fct_or.sk_house_listing, DATE_TRUNC('MONTH',DATE(ct.ts_created)) ORDER BY DATE(ct.ts_created) DESC) AS rn
    FROM 
      dw_retention.fact_owner_retention AS fct_or
    JOIN 
      dw_rent.dim_contract AS dc 
        ON dc.sk_contract = fct_or.sk_contract
    LEFT JOIN 
      datalake_offboarding.contract_termination AS ct 
        ON dc.sk_contract=ct.id_contract
    WHERE 
        dc.status IN ('Ativo', 'Finalizado')  
        AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
        AND DATE(ct.ts_created) >= DATE('2022-01-01')
        AND ct.status <> 'CANCELED'
),
listing_base AS (
  SELECT
    erc.sk_contract,
    termination_request_date,
    erc.termination_date,
    erc.dt_ended_rental_confirmed,
    DATE(dhl_2.ts_publication) AS dt_publication_nxt,
    value_segment,
    erc.sk_house_listing,
    dhl_2.sk_house_listing AS nxt_sk_house_listing,
    DATEDIFF(DATE(dhl_2.ts_publication), erc.termination_request_date) AS leadtime_tr_rl
  FROM 
    ended_rentals_requested AS erc
  LEFT JOIN 
    dw_rent.dim_house_listing AS dhl_2 
      ON dhl_2.sk_house_listing = erc.nxt_sk_house_listing
  WHERE
    erc.rn = 1
    AND (erc.country_code = 'BR' OR erc.country_code IS NULL)
    AND DATE(dhl_2.ts_publication) >= ADD_MONTHS(DATE_TRUNC('MONTH', CURRENT_DATE), -13)
    AND DATE(dhl_2.ts_publication) <= DATE_TRUNC('WEEK', CURRENT_DATE)
) 
SELECT  
  DATE_TRUNC('WEEK',dt_publication_nxt) AS relisting_week, 
  value_segment AS category,
  SUM(IF(leadtime_tr_rl <= 3, 1, 0)) AS tr_with_rl_3_days,
  COUNT(DISTINCT nxt_sk_house_listing) AS relistings,
  (CAST(SUM(IF(leadtime_tr_rl <= 3, 1, 0)) AS DOUBLE) / COUNT(DISTINCT nxt_sk_house_listing)) * 100.00 AS pct_tr_with_rl_3_days
FROM 
  listing_base 
GROUP BY 
  1 ,2

UNION 
     
SELECT 
  DATE_TRUNC('WEEK',dt_publication_nxt) AS relisting_week,
  'OVERALL' AS category,
  SUM(IF(leadtime_tr_rl <= 3, 1, 0)) AS tr_with_rl_3_days,
  COUNT(DISTINCT nxt_sk_house_listing) AS relistings,
  (CAST(SUM(IF(leadtime_tr_rl <= 3, 1, 0)) AS DOUBLE) / COUNT(DISTINCT nxt_sk_house_listing)) * 100.00 AS pct_tr_with_rl_3_days
FROM 
  listing_base
GROUP BY 
  1,2