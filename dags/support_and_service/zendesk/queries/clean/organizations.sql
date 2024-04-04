SELECT DISTINCT
  id AS id_organization,
  group_id AS id_group,
  external_id AS id_external,
  name,
  domain_names,
  url,
  organization_fields,
  CAST(shared_tickets AS BOOLEAN) AS has_shared_tickets,
  CAST(shared_comments AS BOOLEAN) AS has_shared_comments,
  tags,
  details,
  notes,
  CAST(dt AS DATE) AS dt_extracted,
  CAST(created_at AS TIMESTAMP) AS ts_created,
  CAST(updated_at AS TIMESTAMP) AS ts_updated,
  CAST(deleted_at AS TIMESTAMP) AS ts_deleted,
  YEAR(CAST(dt AS DATE)) AS year,
  MONTH(CAST(dt AS DATE)) AS month,
  DAY(CAST(dt AS DATE)) AS day
FROM
  datalake_zendesk_raw.organizations
WHERE
  dt IN (MAKE_DATE({year}, {month}, {day}), MAKE_DATE({year}, {month}, {day}) + INTERVAL 1 DAY)
QUALIFY
  ROW_NUMBER() OVER(PARTITION BY id_organization, ts_updated ORDER BY dt_extracted DESC) = 1
