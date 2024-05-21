SELECT
  ARRAY('datahub') AS vendor,
  platform,
  id_dashboard,
  dashboard_path,
  title,
  description,
  NULL AS certified_by,
  NULL AS business_owners,
  ownership AS created_by,
  ownership AS changed_by,
  domain,
  status,
  ids_charts,
  dashboard_url,
  NULL AS created_on,
  NULL AS changed_on,
  NULL as tags
FROM
  datalake_dashboard_governance.dashboard_metadata
WHERE
  day == {day} and month == {month} and year == {year}
UNION ALL
SELECT
  ARRAY('datahub') AS vendor,
  platform,
  CAST(id AS STRING) AS id_dashboard,
  company_line AS dashboard_path,
  entity_name AS title,
  COALESCE(entity_description,"") AS description,
  certified_by,
  business_owners,
  technical_owner AS created_by,
  last_owner AS changed_by,
  company_line AS domain,
  entity_status AS status,
  TRANSFORM(lineage_charts, x->CAST(x AS STRING) ) AS ids_charts,
  entity_url AS dashboard_url,
  date_format(ts_created, 'yyyy-MM-dd hh:mm:ss') AS created_on,
  date_format(ts_changed, 'yyyy-MM-dd hh:mm:ss') AS changed_on,
  tags
FROM 
    datalake_superset.dashboards
WHERE published = true