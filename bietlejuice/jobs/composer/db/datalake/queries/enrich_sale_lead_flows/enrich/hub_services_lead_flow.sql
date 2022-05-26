-- VISITOR
WITH visitor AS (
  SELECT
    id,
    id_external,
    email,
    phone_number,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated) AS rw_asc
  FROM
    datalake_hub_services_clean.visitor
),

-- HOUSE
house AS (
  SELECT
    id,
    id_region,
    city
  FROM 
    datalake_ebdb_clean.house AS h
),

-- LEAD TALK TO SECRETARIAT
talk_to_secretariat AS (
  SELECT
    id_visitor,
    ts_created,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated) AS rw_asc,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated DESC) AS rw_desc
  FROM 
    datalake_hub_services_clean.lead_aud AS l
  WHERE
    lead_type = 'TALK_TO_SECRETARIA'
),

first_talk_to_secretariat AS (
  SELECT
    id_visitor,
    ts_created
  FROM
    talk_to_secretariat
  WHERE
    rw_asc = 1
),

last_talk_to_secretariat AS (
  SELECT
    id_visitor,
    ts_created
  FROM
    talk_to_secretariat
  WHERE
    rw_desc = 1
),

-- LEAD CONTACT PROSPECT
contact_prospect AS (
  SELECT
    id_visitor,
    h.id_region,
    r.name AS region_name,
    h.city AS city_name,
    is_secretariat,
    l.ts_created,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated) AS rw_asc,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated DESC) AS rw_desc
  FROM 
    datalake_hub_services_clean.lead_aud AS l
  LEFT JOIN
    house AS h
      ON l.id_house = h.id
  LEFT JOIN
    datalake_ebdb_clean.region AS r
      ON h.id_region = r.id
  WHERE
    UPPER(lead_status) = 'SENT_TO_CASA_MINEIRA'
    OR UPPER(lead_status) = 'PROCESSED' 
    AND is_secretariat = true
),

first_contact_prospect AS (
  SELECT
    id_visitor,
    id_region,
    region_name,
    city_name,
    ts_created
  FROM
    contact_prospect
  WHERE
    rw_asc = 1
),

last_contact_prospect AS (
  SELECT
    id_visitor,
    id_region,
    region_name,
    city_name,
    ts_created
  FROM
    contact_prospect
  WHERE
    rw_desc = 1
),

-- LEADS
leads AS (
  SELECT 
    l.id_visitor,
    v.id_external,
    l.id_house,
    h.id_region,
    l.id_business_unit,
    v.email,
    v.phone_number,
    COALESCE(bur.business_unit, 'not_mapped') AS business_unit_hub_name, 
    l.lead_type,
    l.lead_status,
    l.ts_created,
    l.ts_updated,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated) AS rw_offer_asc,
    ROW_NUMBER() OVER (PARTITION BY l.id_visitor ORDER BY l.ts_updated DESC) AS rw_offer_desc
  FROM 
    datalake_hub_services_clean.lead_aud AS l
  LEFT JOIN
    visitor AS v
      ON l.id_visitor = v.id
  LEFT JOIN
    house AS h
      ON l.id_house = h.id
  LEFT JOIN
    datalake_gsheets_clean.business_unit_region AS bur
      ON h.id_region = bur.id_region
      AND (DATE(l.ts_created) BETWEEN bur.dt_start AND COALESCE(bur.dt_end, DATE_SUB(CURRENT_DATE, 1)))
  WHERE 
    l.business_context = 'SALE'
    AND v.rw_asc = 1
),

first_lead AS (
  SELECT * 
  FROM
    leads
  WHERE 
    rw_offer_asc = 1
),

last_lead AS (
  SELECT * 
  FROM
    leads
  WHERE 
    rw_offer_desc = 1
)

SELECT 
  fl.id_visitor,
  fl.id_external,
  fl.id_house AS id_first_house,
  ll.id_house AS id_last_house,
  fl.id_region AS id_first_region,
  fcp.id_region AS id_first_contact_prospect_region,
  lcp.id_region AS id_last_contact_prospect_region,
  fl.id_business_unit AS id_first_business_unit,
  ll.id_business_unit AS id_last_business_unit,
  fl.email,
  fl.phone_number,
  UPPER(fl.lead_type) AS first_contact_prospect_type,
  'QUINTO_ANDAR' AS first_contact_prospect_origin,
  'QUINTO_ANDAR' AS last_contact_prospect_origin,
  UPPER(fl.lead_type) AS first_contact_prospect_midia,
  UPPER(ll.lead_type) AS last_contact_prospect_midia,
  fcp.region_name AS first_contact_prospect_region_name,
  lcp.region_name AS last_contact_prospect_region_name,
  fcp.city_name AS first_contact_prospect_city_name,
  lcp.city_name AS last_contact_prospect_city_name,
  fl.business_unit_hub_name AS first_business_unit_hub_name,
  ll.business_unit_hub_name AS last_business_unit_hub_name,
  TRUE AS has_secretariat_contact_created,
  fl.ts_created AS ts_first_visit_lead_intent,
  ll.ts_created AS ts_last_visit_lead_intent,
  fts.ts_created AS ts_first_talk_to_secretariat,
  lts.ts_created AS ts_last_talk_to_secretariat,
  fcp.ts_created AS ts_first_contact_prospect,
  lcp.ts_created AS ts_last_contact_prospect
FROM 
  first_lead AS fl
INNER JOIN
  last_lead AS ll
    ON fl.id_visitor = ll.id_visitor
LEFT JOIN
  first_talk_to_secretariat AS fts
    ON fl.id_visitor = fts.id_visitor
LEFT JOIN
  last_talk_to_secretariat AS lts
    ON fl.id_visitor = lts.id_visitor
LEFT JOIN
  first_contact_prospect AS fcp
    ON fl.id_visitor = fcp.id_visitor
LEFT JOIN
  last_contact_prospect AS lcp
    ON fl.id_visitor = lcp.id_visitor
