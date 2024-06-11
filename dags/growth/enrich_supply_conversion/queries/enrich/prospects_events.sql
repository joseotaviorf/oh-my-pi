WITH extracted AS (
  SELECT 
    id AS id_prospect,
    is_for_rent,
    is_for_sale
  FROM datalake_wololo_clean.prospect
),
corner_cases AS (
  SELECT 
    id_prospect,
    'RENT' AS bc_rent,
    'SALE' AS bc_sale
  FROM extracted
  WHERE is_for_rent IS FALSE
    AND is_for_sale IS FALSE
),
fill_bc AS (
  SELECT 
    id_prospect,
    IF(COALESCE(is_for_rent, TRUE), 'RENT', NULL) AS bc_rent,
    IF(COALESCE(is_for_sale, TRUE), 'SALE', NULL) AS bc_sale
  FROM extracted
  WHERE NOT(is_for_rent IS FALSE
    AND is_for_sale IS FALSE)
),
pivot_tb AS (
  SELECT 
    id_prospect,
    EXPLODE(ARRAY(bc_rent, bc_sale)) AS business_context
  FROM fill_bc
  UNION ALL
  SELECT 
    id_prospect,
    EXPLODE(ARRAY(bc_rent, bc_sale)) AS business_context
  FROM corner_cases
),
prospect_business_context AS (
  SELECT *
  FROM pivot_tb
  WHERE business_context IS NOT NULL
),
extract_wololo AS (
  SELECT
    p.id AS id_prospect,
    p.id_reference AS id_lead_ebdb,
    p.id_external AS id_lead_rene,
    p.status,
    bc.business_context,
    p.ts_created,
    p.ts_updated
  FROM
    datalake_wololo_clean.prospect AS p
  LEFT JOIN prospect_business_context AS bc
    ON (p.id = bc.id_prospect)
)

SELECT
  id_prospect AS id_entity,
  id_prospect AS id_source,
  cd.id_user AS id_user_registrant,
  p.id_lead_ebdb AS id_lead,
  cd.id AS rev,
  business_context,
  p.status,
  'WOLOLO' AS source,
  'PROSPECT' AS step,
  4 AS weight,
  cd.reason,
  sds.drop_step,
  cd.ts_created AS ts_event
FROM
  extract_wololo AS p
JOIN datalake_wololo_clean.context_discard AS cd
  USING (id_prospect, business_context)
LEFT JOIN datalake_supply_flows.supply_discards_settings AS sds
  ON cd.reason = sds.discards_reason