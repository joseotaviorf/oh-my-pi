WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_zendesk_tickets_raw.organizations
    GROUP BY 1
)
SELECT
  o.id,
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
  CAST(updated_at AS TIMESTAMP) AS ts_updated,
  CAST(created_at AS TIMESTAMP) AS ts_created,
  CAST(deleted_at AS TIMESTAMP) AS ts_deleted,
  YEAR(CAST(o.updated_at AS DATE)) AS year,
  MONTH(CAST(o.updated_at AS DATE)) AS month,
  DAY(CAST(o.updated_at AS DATE)) AS day
FROM
  datalake_zendesk_tickets_raw.organizations o
JOIN
    max_stitch_data max_sd
        ON max_sd.id = o.id
        AND max_sd.max_updated_at = CAST(o.updated_at AS TIMESTAMP)
