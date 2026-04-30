WITH vsl AS (
  SELECT
    id_visit_status_log,
    id_visit,
    id_schedule,
    id_author_user,
    author_user_type,
    author_user_role,
    on_behalf_of,
    channel,
    application_source,
    reason,
    event_type,
    ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created ASC) AS ranking,
    CASE
      WHEN ROW_NUMBER() OVER(PARTITION BY id_visit ORDER BY ts_created DESC) == 1 THEN TRUE
      ELSE FALSE
    END AS is_visit_last_event,
    ts_created,
    ts_updated
  FROM
    datalake_ebdb_clean.visit_status_log
)
  SELECT
    CONCAT(vsl.id_visit_status_log,'R',vsl.ranking) AS id_visit_status_events,
    vsl.id_visit_status_log,
    vsl.id_visit,
    vsl.id_schedule,
    vsl.id_author_user,
    v.id_visitor,
    v.id_agent,
    v.id_house,
    COALESCE(hl.id_house_listing, -1) AS id_house_listing,
    lh.id_user AS id_owner,
    -1 AS id_rent_flow,
    'NA' AS id_sale_flow, --esse id é um coalesce
    -1 AS id_fup_details,
    vbm.sk_broker_supply,
    vbm.sk_broker_demand,
    vbm.id_company_supply,
    vbm.id_company_demand,
    lh.uuid_company AS uuid_company_supply,
    v.business_context,
    vsl.event_type,
    vsl.ranking,
    vsl.author_user_type,
    vsl.author_user_role,
    vsl.on_behalf_of,
    vsl.channel,
    vsl.application_source,
    vsl.reason,
    vbm.partner_3p_supply,
    vbm.partner_3p_demand,
    hl.country_code,
    vbm.is_3p_supply,
    vbm.is_3p_demand,
    vbm.is_3p_lead_gen,
    vbm.has_3p_access_control,
    vsl.is_visit_last_event,
    vsl.ts_created,
    vsl.ts_updated
  FROM
    datalake_ebdb_clean.visit AS v
  INNER JOIN
    vsl
      ON  v.id = vsl.id_visit
  INNER JOIN
    datalake_ebdb_listing.house lh
      ON lh.id = v.id_house
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON v.id_house = hl.id_house
      AND DATE(v.ts_created) >= DATE(hl.ts_listing_version_start)
      AND (DATE(v.ts_created) < DATE(hl.ts_listing_version_end) OR hl.ts_listing_version_end IS NULL)
  LEFT JOIN
    datalake_visit.visit_business_model AS vbm
      ON v.id = vbm.id_visit
  WHERE
    DATE(v.ts_created) >= '2024-11-01'
