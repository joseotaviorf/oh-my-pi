SELECT
    id AS id_group,
    url AS url_group,
    name,
    deleted AS is_deleted,
    dt AS dt_extracted,
    FROM_UTC_TIMESTAMP(CAST(created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(updated_at AS DATE)) AS year,
    MONTH(CAST(updated_at AS DATE)) AS month,
    DAY(CAST(updated_at AS DATE)) AS day
FROM
    datalake_zendesk_tickets_raw.groups
QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
