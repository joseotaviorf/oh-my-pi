SELECT DISTINCT
  id AS id_organization,
  group_id AS id_group,
  external_id AS id_external,
  name,
  domain_names,
  url,
  organization_fields,
  shared_tickets AS has_shared_tickets,
  shared_comments AS has_shared_comments,
  tags,
  details,
  notes,
  CAST(dt AS DATE) AS dt_extracted,
  CAST(created_at AS TIMESTAMP) AS ts_created,
  CAST(updated_at AS TIMESTAMP) AS ts_updated,
  CAST(deleted_at AS TIMESTAMP) AS ts_deleted,
  YEAR(dt) AS year,
  MONTH(dt) AS month,
  DAY(dt) AS day
FROM
  datalake_zendesk_raw.organizations
WHERE
  dt IN ('{year}-{month}-{day}', CAST((CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY) AS STRING))
