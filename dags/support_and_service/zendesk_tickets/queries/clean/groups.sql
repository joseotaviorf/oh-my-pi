WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_zendesk_tickets_raw.groups
    GROUP BY 1
)
SELECT
    gp.id AS id_group,
    gp.url AS url_group,
    gp.name,
    gp.deleted AS is_deleted,
    gp.dt AS dt_extracted,
    FROM_UTC_TIMESTAMP(CAST(gp.created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(gp.created_at AS TIMESTAMP) AS ts_created,
    CAST(gp.updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(gp.updated_at AS DATE)) AS year,
    MONTH(CAST(gp.updated_at AS DATE)) AS month,
    DAY(CAST(gp.updated_at AS DATE)) AS day
FROM
    datalake_zendesk_tickets_raw.groups gp
JOIN
    max_stitch_data max_sd
        ON max_sd.id = gp.id
        AND max_sd.max_updated_at = CAST(gp.updated_at AS TIMESTAMP)
