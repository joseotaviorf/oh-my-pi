SELECT
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
  dt AS dt_extracted,
  updated_at AS ts_updated,
  created_at AS ts_created,
  deleted_at AS ts_deleted,
  YEAR(dt) AS year,
  MONTH(dt) AS month,
  DAY(dt) AS day
FROM
  datalake_zendesk_raw.organizations
WHERE
  dt IN (CAST('{year}-{month}-{day}' AS DATE), CAST('{year}-{month}-{day}' AS DATE) + INTERVAL 1 DAY)
