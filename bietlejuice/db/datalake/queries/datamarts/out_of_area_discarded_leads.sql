WITH
radius AS (
  -- here we define our tolerance radius of out of area leads, in km
  SELECT 1.0 AS "radius_km"
),
user_affiliate as (
  SELECT
    u.dados_afiliado_id,
    u.sk_user
  FROM datalake_clean.ods_dim_user AS u
  JOIN datalake_clean.ods_dim_user_affiliate AS a
    ON u.dados_afiliado_id = a.sk_user_affiliate
    and u.dados_afiliado_id is not null
),
discarded_leads AS (
  SELECT
    dim_date_lead.date AS "date_lead",
    dim_lead.sk_lead AS "sk_lead",
    dim_lead.id AS "id",
    dim_lead.status AS "status",
    dim_lead.tipo AS "tipo",
    dim_lead.telefone_anunciante AS "telefone_anunciante",
    dim_lead.proprietario_nome AS "proprietario_nome",
    dim_lead.proprietario_email AS "proprietario_email",
    dim_lead.email AS "email",
    dim_lead.email_captador AS "email_captador",
    dim_lead.lng AS "lng",
    dim_lead.lat AS "lat",
    dim_lead.endereco AS "endereco",
    dim_lead.cidade AS "cidade",
    dim_lead.captado_em AS "captado_em_date",
    fact_house_listing_flows.mkt_channel AS "mkt_channel",
    fact_house_listing_flows.mkt_medium AS "mkt_medium",
    fact_house_listing_flows.lead_type AS "lead_type",
    user_affiliate.dados_afiliado_id AS "dados_afiliado_id"
  FROM datalake_clean.ods_fact_house_listing_flows AS fact_house_listing_flows
  LEFT JOIN datalake_clean.ods_dim_lead AS dim_lead ON fact_house_listing_flows.sk_lead = dim_lead.sk_lead
  LEFT JOIN datalake_clean.ods_dim_region AS dim_region ON dim_region.sk_region = fact_house_listing_flows.sk_region
  FULL OUTER JOIN user_affiliate ON fact_house_listing_flows.sk_user_lead_affiliate = user_affiliate.sk_user
  LEFT JOIN datalake_clean.ods_dim_date AS dim_date_lead ON dim_date_lead.sk_date = fact_house_listing_flows.sk_lead_date
  WHERE (dim_lead.reason = 'ForaArea') AND (dim_lead.status = 'Descartado')
    AND TRY(DATE(dim_date_lead.date))  >= CURRENT_DATE - INTERVAL '30' day
    AND fact_house_listing_flows.sk_prospect_date = '-1'
  GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19
),
subregions AS (
	SELECT r.*, p.polygon AS geometry
	FROM datalake_clean.ods_dim_region r
	JOIN datalake_ebdb_clean_prod.polygon_region p ON cast(r.sk_region as bigint) = p.id_region
	WHERE level = 'SubRegiao'
),
discarded_leads_subregions AS (
	SELECT
    dl.*,
    r.sk_region AS current_sk_region,
    r.name AS current_region_name,
    r.city_name AS current_city_name,
    r.city_group AS current_city_group,
    r.regional AS current_regional,
    CEIL(ST_DISTANCE(
      ST_POINT(TRY(CAST(dl.lng AS REAL)), TRY(CAST(dl.lat AS REAL))),
      r.geometry
    ) * (111.321 * COS(RADIANS(ST_MIN_Y(r.geometry)))) * 1000) AS lead_distance_meters_from_current_region
	FROM discarded_leads dl
	JOIN subregions r
	ON
    -- within a certain radius of a currently existing region
    (
      ST_DISTANCE(
        ST_POINT(TRY(CAST(dl.lng AS REAL)), TRY(CAST(dl.lat AS REAL))),
        r.geometry
      ) <= ((SELECT radius_km FROM radius) / (111.321 * COS(RADIANS(ST_MIN_Y(r.geometry)))))
    )
),
distance_order AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY sk_lead ORDER BY lead_distance_meters_from_current_region) AS distance_order
  FROM discarded_leads_subregions
)
SELECT
  *,
  CASE
    WHEN lead_distance_meters_from_current_region = 0 THEN '0'
    WHEN lead_distance_meters_from_current_region > 0 AND lead_distance_meters_from_current_region <= 250 THEN '1-250'
    WHEN lead_distance_meters_from_current_region > 250 AND lead_distance_meters_from_current_region <= 500 THEN '251-500'
    WHEN lead_distance_meters_from_current_region > 500 AND lead_distance_meters_from_current_region <= 1000 THEN '501-1000'
  END AS distance_category_meters,
  CASE
    WHEN lead_distance_meters_from_current_region = 0 THEN 'Lead inside existing region'
    ELSE 'Lead near existing region'
  END AS reprocessed_lead_type
FROM distance_order
WHERE distance_order = 1
