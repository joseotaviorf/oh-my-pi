WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_velo_zendesk_raw.organizations
)
SELECT
    id,
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
    YEAR(CAST(updated_at AS DATE)) AS year,
    MONTH(CAST(updated_at AS DATE)) AS month,
    DAY(CAST(updated_at AS DATE)) AS day
FROM
    ranked
WHERE
    rn = 1
