SELECT
    id AS id_pipeline,
    label,
    stages,
    display_order,
    archived AS is_archived,
    archived_at AS ts_archived,
    created_at AS ts_created,
    updated_at AS ts_updated,
    ts_load,
    YEAR(updated_at) AS year,
    MONTH(updated_at) AS month,
    DAY(updated_at) AS day
FROM
    datalake_hubspot_test_raw.ticket_pipeline
WHERE
    ts_load BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
