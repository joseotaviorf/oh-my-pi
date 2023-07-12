SELECT
    *,
    DATE(updated_at) AS dt
FROM
    similar_property_aud
WHERE
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')