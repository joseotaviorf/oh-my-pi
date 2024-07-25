WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_velo_zendesk_raw.group_memberships
    GROUP BY 1
)
SELECT
    gm.id AS id_group_memberships,
    gm.group_id AS id_group,
    gm.user_id AS id_user,
    gm.url AS url_group_memberships,
    gm.default AS is_default,
    gm.dt AS dt_extracted,
    CAST(gm.created_at AS TIMESTAMP) AS ts_created,
    FROM_UTC_TIMESTAMP(CAST(gm.created_at AS TIMESTAMP), 'Brazil/East') AS ts_created_local,
    CAST(gm.updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(gm.updated_at AS DATE)) AS year,
    MONTH(CAST(gm.updated_at AS DATE)) AS month,
    DAY(CAST(gm.updated_at AS DATE)) AS day
FROM
    datalake_velo_zendesk_homolog_raw.group_memberships gm
JOIN
    max_stitch_data max_sd
        ON max_sd.id = gm.id
        AND max_sd.max_updated_at = CAST(gm.updated_at AS TIMESTAMP)
