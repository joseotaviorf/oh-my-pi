WITH 
house_listing_contracts AS (
  SELECT
    hl.id_house_listing,
    c.id AS id_contract,
    hl.id_house,
    hl.version AS house_version,
    c.ts_signed AS ts_contract_signed,
    c.dt_termination AS dt_contract_annulment
  FROM
    datalake_ebdb_listing.house_listing AS hl
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON hl.id_house = c.id_house
        AND c.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '2000-01-01 00:00:00') AND COALESCE(hl.ts_listing_version_end, CURRENT_DATE)
        AND c.status IN ('Ativo', 'Finalizado')
),
ended_rentals_confirmed AS (
  SELECT 
    hl.id_house_listing AS sk_house_listing,
    hl.id_house,
    (hl.id_house_listing + 1) AS nxt_sk_house_listing,
    dc.sk_contract, 
    dc.rent,
    dc.value_segment,
    dc.country_code,
    DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment)) AS dt_ended_rental_confirmed,
    ROW_NUMBER() OVER(PARTITION BY hl.id_house_listing, DATE_TRUNC('MONTH',DATE(COALESCE(dc.ts_analyst_annulment_input,dc.dt_annulment))) ORDER BY DATE(coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment)) DESC) AS rn
  FROM 
    datalake_ebdb_listing.house_listing AS hl 
  JOIN
    house_listing_contracts AS hlc
      ON hlc.id_house_listing = hl.id_house_listing
  JOIN 
    dw_rent.dim_contract AS dc 
      ON dc.sk_contract = hlc.id_contract
  WHERE 
    dc.status IN ('Finalizado')  
    AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
    AND coalesce(dc.ts_analyst_annulment_input,dc.dt_annulment) IS NOT NULL
  QUALIFY 
    rn = 1
),
contract_signed AS (
  SELECT
    DATE(dc.ts_signature) AS contract_signed_date,
    DATE_TRUNC('MONTH', dc.ts_signature) AS contract_signed_month,
    hlc.id_house_listing AS sk_house_listing,
    hlc.id_contract AS sk_contract,
    dc.value_segment
  FROM 
    house_listing_contracts AS hlc 
  JOIN 
    dw_rent.dim_contract AS dc 
      ON hlc.id_contract = dc.sk_contract
  WHERE
    dc.ts_signature IS NOT NULL
    AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
    AND IF(dc.status IN ('Ativo','Finalizado'), TRUE, FALSE)
    AND dc.ts_signature < CURRENT_DATE
  GROUP BY
    1,2,3,4,5
),
ended_rentals_requested AS ( 
  SELECT 
    hl.id_house_listing AS sk_house_listing,
    hl.id_house,
    (hl.id_house_listing + 1) AS nxt_sk_house_listing,
    dc.sk_contract, 
    dc.country_code,
    ct.ts_created AS termination_request_date,
    ct.dt_termination AS termination_date,
    dc.value_segment,
    ROW_NUMBER() OVER(PARTITION BY hl.id_house_listing, DATE_TRUNC('MONTH',DATE(ct.ts_created)) ORDER BY DATE(ct.ts_created) DESC) AS rn
  FROM 
    datalake_ebdb_listing.house_listing AS hl 
  JOIN
    house_listing_contracts AS hlc
      ON hlc.id_house_listing = hl.id_house_listing
  JOIN 
    dw_rent.dim_contract AS dc 
      ON dc.sk_contract = hl.id_contract
  LEFT JOIN 
    datalake_offboarding.contract_termination AS ct 
      ON dc.sk_contract=ct.id_contract
  WHERE 
    dc.status IN ('Ativo', 'Finalizado')  
    AND (dc.country_code = 'BR' OR dc.country_code IS NULL)
    AND DATE(ct.ts_created) >= DATE('2022-01-01')
    AND ct.status <> 'CANCELED'
),
relisting_base AS (
  SELECT
    erc.sk_contract,
    termination_request_date,
    erc.termination_date,
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
    AND DATE(dhl_2.ts_publication) <= DATE_TRUNC('MONTH', CURRENT_DATE)
) 
SELECT 
    hl.id_house_listing AS sk_house_listing,
    hl.id_house AS sk_house,
    h.id_user AS sk_owner,
    dc.id AS sk_contract,
    hl.country_code,
    rl.leadtime_tr_rl AS days_until_next_listing,
    DATEDIFF(cs.contract_signed_date, erc.dt_ended_rental_confirmed) AS days_until_next_rental,
    NOW() AS ts_load
FROM
  datalake_ebdb_listing.house_listing AS hl
JOIN
  datalake_ebdb_listing.house AS h
    ON h.id = hl.id_house
LEFT JOIN 
  house_listing_contracts AS hlc
    ON hlc.id_house_listing = hl.id_house_listing
LEFT JOIN
  datalake_ebdb_contract.contract AS dc
    ON dc.id = hlc.id_contract
LEFT JOIN 
  ended_rentals_confirmed AS erc
    ON erc.sk_contract = dc.id
LEFT JOIN
  contract_signed AS cs
    ON cs.sk_house_listing = hl.id_house_listing + 1
LEFT JOIN
  relisting_base AS rl
    ON rl.sk_contract = dc.id
