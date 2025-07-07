SELECT
    id,
    relationships[0].user.data.id AS id_user,
    attributes.title,
    attributes.image_url AS url_image,
    attributes.rating,
    TO_TIMESTAMP(attributes.started_at) AS ts_started,
    TO_TIMESTAMP(attributes.completed_at) AS ts_completed,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.accomplishments
WHERE
    DATE(attributes.started_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
