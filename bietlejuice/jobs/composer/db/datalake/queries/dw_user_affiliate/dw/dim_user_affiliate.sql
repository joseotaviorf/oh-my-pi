WITH affiliates_full AS (
  SELECT
    ad.id AS sk_user_affiliate,
    ad.id AS id_user_affiliate,
    ad.id_indicated_by AS sk_user_indicated_by,
    u.id AS id_user,
    ad.is_active,
    ad.origin,
    ad.affiliate_type,
    COALESCE(agent_data.is_realstate_agent, FALSE) AS is_realstate_agent,
    COALESCE(agent_data.is_photographer, FALSE) AS is_photographer,
    u.main_phone_ddd AS main_phone_ddd,
    uao.utm_source AS tracking_source,
    uao.utm_medium AS tracking_medium,
    uao.utm_campaign AS tracking_campaign,
    uao.utm_content AS tracking_content,
    uao.utm_term AS tracking_term,
    uao.city_campaign,
    uao.platform AS tracking_platform,
    uao.device_type AS tracking_device_type,
    uao.country AS tracking_country,
    uao.region AS tracking_state,
    uao.city AS tracking_city,
    ad.ts_operation_start,
    ad.ts_created,
    ad.ts_updated
  FROM
    datalake_ebdb_user.affiliate_data AS ad
  JOIN
    datalake_ebdb_user.user AS u
      ON u.id_affiliates = ad.id
  LEFT JOIN
    datalake_amplitude_user.user_affiliate_origin AS uao
      ON u.id = uao.id_user
  LEFT JOIN
    datalake_ebdb_user.agent_data
      ON agent_data.id = u.id_agent
),
region_ddd AS (
  SELECT DISTINCT
    city_group,
    city_ddd AS ddd,
    regional
  FROM
    datalake_region.region
  WHERE
    is_city
),
region_city AS (
  SELECT DISTINCT
    city_name,
    city_group,
    regional
  FROM
    datalake_region.region
  WHERE
    is_city
),
affiliate_mkt_city_group AS (
  SELECT
    af_full.*,
    COALESCE(af_full.city_campaign, region_city.city_group, region_ddd.city_group) AS marketing_city_group,
    COALESCE(region_city.regional, region_ddd.regional) AS regional_ddd_city
  FROM
    affiliates_full AS af_full
  LEFT JOIN
    region_city
      ON af_full.tracking_city = region_city.city_name
  LEFT JOIN
    region_ddd
      ON af_full.main_phone_ddd = region_ddd.ddd
      AND region_ddd.city_group = region_city.city_group
),
aff_city_group_with_region AS (
  SELECT
    aff_city_region.sk_user_affiliate,
    aff_city_region.id_user_affiliate,
    aff_city_region.sk_user_indicated_by,
    aff_city_region.id_user,
    aff_city_region.origin,
    aff_city_region.affiliate_type,
    aff_city_region.marketing_city_group,
    COALESCE(region_city_group.regional, aff_city_region.regional_ddd_city) AS regional,
    NULLIF(aff_city_region.tracking_source, '') AS tracking_source,
    NULLIF(aff_city_region.tracking_medium, '') AS tracking_medium,
    NULLIF(aff_city_region.tracking_campaign, '') AS tracking_campaign,
    NULLIF(aff_city_region.tracking_content, '') AS tracking_content,
    NULLIF(aff_city_region.tracking_term, '') AS tracking_term,
    aff_city_region.tracking_platform,
    aff_city_region.tracking_device_type,
    aff_city_region.tracking_country,
    aff_city_region.tracking_state,
    aff_city_region.tracking_city,
    aff_city_region.is_realstate_agent,
    aff_city_region.is_active,
    aff_city_region.is_photographer,
    aff_city_region.ts_operation_start,
    aff_city_region.ts_created,
    aff_city_region.ts_updated
  FROM
    affiliate_mkt_city_group AS aff_city_region
  LEFT JOIN
    region_ddd AS region_city_group
      ON aff_city_region.marketing_city_group = region_city_group.city_group
),
taxonomy AS (
  SELECT
    affiliate_type,
    tracking_medium,
    tracking_source,
    tracking_campaign,
    COALESCE(mkt_origin, '') AS mkt_origin,
    COALESCE(mkt_channel, '') AS mkt_channel,
    COALESCE(mkt_medium, '') AS mkt_medium,
    COALESCE(mkt_source, '') AS mkt_source
  FROM
    datalake_gsheets_clean.taxonomy_affiliates
),
applied_taxonomy AS (
  SELECT
    acg.*,
    COALESCE(tax.mkt_origin, 'Other') AS mkt_origin,
    COALESCE(tax.mkt_channel, 'Not Mapped') AS mkt_channel,
    COALESCE(tax.mkt_medium, 'Not Mapped') AS mkt_medium,
    COALESCE(tax.mkt_source, 'Not Mapped') AS mkt_source
  FROM
    aff_city_group_with_region AS acg
  LEFT JOIN
    taxonomy AS tax
      ON COALESCE(tax.affiliate_type, '') = COALESCE(acg.affiliate_type, '')
      AND COALESCE(tax.tracking_medium, '') = COALESCE(acg.tracking_medium, '')
      AND COALESCE(tax.tracking_source, '') = COALESCE(acg.tracking_source, '')
      AND COALESCE(tax.tracking_campaign, '') = COALESCE(acg.tracking_campaign, '')
  )
SELECT
  atax.sk_user_affiliate,
  atax.id_user AS sk_user,
  atax.id_user_affiliate,
  atax.sk_user_indicated_by,
  atax.origin,
  atax.affiliate_type,
  atax.marketing_city_group,
  atax.regional,
  atax.tracking_source,
  atax.tracking_medium,
  atax.tracking_campaign,
  atax.tracking_content,
  atax.tracking_term,
  atax.tracking_platform,
  atax.tracking_device_type,
  atax.tracking_country,
  atax.tracking_state,
  atax.tracking_city,
  atax.mkt_origin,
  atax.mkt_channel,
  atax.mkt_medium,
  atax.mkt_source,
  atax.is_realstate_agent,
  atax.is_photographer,
  atax.is_active,
  atax.ts_operation_start,
  atax.ts_created,
  atax.ts_updated,
  NOW() AS ts_load
FROM
  applied_taxonomy AS atax
