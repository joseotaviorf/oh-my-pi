WITH max_stitch_data AS (
    SELECT
        id,
        MAX(CAST(updated_at AS TIMESTAMP)) AS max_updated_at
    FROM
        datalake_velo_zendesk_homolog_raw.ticket_fields
    GROUP BY 1
)
SELECT
    tf.id AS id_ticket_fields,
    tf.title,
    tf.description,
    tf.agent_description,
    tf.url AS url_ticket_fields,
    tf.raw_title,
    tf.raw_title_in_portal,
    tf.raw_description,
    tf.custom_field_options,
    tf.removable AS is_removable,
    tf.position AS is_position,
    tf.required AS is_required,
    tf.type,
    tf.active AS is_active,
    tf.collapsed_for_agents AS is_collapsed_for_agents,
    tf.visible_in_portal AS is_visible_in_portal,
    tf.required_in_portal AS is_required_in_portal,
    tf.editable_in_portal AS is_editable_in_portal,
    tf.title_in_portal AS is_title_in_portal,
    tf.dt AS dt_extracted,
    CAST(FROM_UTC_TIMESTAMP(tf.created_at, 'Brazil/East') AS TIMESTAMP) AS ts_created_local,
    CAST(tf.created_at AS TIMESTAMP) AS ts_created,
    CAST(tf.updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    YEAR(CAST(tf.updated_at AS DATE)) AS year,
    MONTH(CAST(tf.updated_at AS DATE)) AS month,
    DAY(CAST(tf.updated_at AS DATE)) AS day
FROM
    datalake_velo_zendesk_homolog_raw.ticket_fields tf
JOIN
    max_stitch_data max_sd
        ON max_sd.id = tf.id
        AND max_sd.max_updated_at = CAST(tf.updated_at AS TIMESTAMP)
