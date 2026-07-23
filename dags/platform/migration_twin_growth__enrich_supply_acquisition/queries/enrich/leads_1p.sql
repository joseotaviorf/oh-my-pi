WITH extracted AS (
  SELECT 
    hl.id AS id_lead,
    CAST(GET_JSON_OBJECT(amd.house_info, '$.forRent') AS BOOLEAN) AS is_for_rent,
    CAST(GET_JSON_OBJECT(amd.house_info, '$.forSale') AS BOOLEAN) AS is_for_sale
  FROM 
    datalake_rene_descartes_clean.house_lead AS hl
  LEFT JOIN 
    datalake_rene_descartes_clean.acquisition_misc_data AS amd
      ON hl.id_acquisition = amd.id
  WHERE DATE(hl.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')  
),
corner_cases AS (
  SELECT 
    id_lead,
    'RENT' AS bc_rent,
    'SALE' AS bc_sale
  FROM 
    extracted
  WHERE 
    is_for_rent IS FALSE
    AND is_for_sale IS FALSE
),
fill_bc AS (
  SELECT 
    id_lead,
    IF(COALESCE(is_for_rent, TRUE), 'RENT', NULL) AS bc_rent,
    IF(COALESCE(is_for_sale, TRUE), 'SALE', NULL) AS bc_sale
  FROM 
    extracted
  WHERE 
    NOT(is_for_rent IS FALSE
    AND is_for_sale IS FALSE)
),
pivot_tb AS (
  SELECT 
    id_lead,
    EXPLODE(ARRAY(bc_rent, bc_sale)) AS business_context
  FROM 
    fill_bc
  UNION ALL
  SELECT 
    id_lead,
    EXPLODE(ARRAY(bc_rent, bc_sale)) AS business_context
  FROM 
    corner_cases
),
lead_business_context AS (
    SELECT 
      id_lead,
      business_context
    FROM 
      pivot_tb
    WHERE 
      business_context IS NOT NULL
),
lead_step AS (
  SELECT 
    s.sk_supply_lead,
    hl.id AS id_lead,
    hl.id_lead_ebdb,
    COALESCE(a.region, ebdb_lead.id_region, rrl.id_region) AS id_region,
    hl.id_referred_by,
    'acquisition_tof2l' AS business_event,
    'LEAD' AS funnel_step,
    '1P' AS supply_source,
    COALESCE(hl_aud.status, 'NEW') AS aux_product_status, -- Fill with new when we have NULL on status
    hl.ts_created AS ts_event -- Creation of lead in Rene
  FROM
    datalake_supply_flows.leads_sks AS s
  LEFT JOIN
    datalake_rene_descartes_clean.house_lead AS hl
      ON hl.id = s.id_lead
  LEFT JOIN 
    datalake_rene_descartes_clean.house_lead_aud AS hl_aud
      ON hl.id = hl_aud.id
  LEFT JOIN 
    datalake_rene_descartes_clean.address AS a
      ON hl.id_address = a.id
      AND a.region IS NOT NULL
  LEFT JOIN 
    datalake_ebdb_clean.lead AS ebdb_lead
      ON hl.id_lead_ebdb = ebdb_lead.id
  LEFT JOIN 
    datalake_supply_flows.recovered_region_leads AS rrl -- ID_REGION RECUPERADO POR MEIO DO LAT/LNG
      ON (hl.id = rrl.id_lead)
  WHERE 
    DATE(hl.ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')  
      AND s.source = '1P'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY s.sk_supply_lead ORDER BY hl_aud.rev) = 1 -- I am looking for the first entry event of Rene
)

SELECT 
  l.sk_supply_lead,
  lead_bc.business_context,
  l.id_lead,
  l.id_lead_ebdb,
  l.id_referred_by,
  l.id_region,
  l.business_event,
  l.funnel_step,
  l.supply_source,
  l.aux_product_status,
  1 AS funnel_level,
  l.ts_event,
  CURRENT_TIMESTAMP() AS ts_load
FROM 
  lead_step AS l
LEFT JOIN 
  lead_business_context AS lead_bc
    ON (l.id_lead = lead_bc.id_lead)