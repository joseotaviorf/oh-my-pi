SELECT
    id,
    relationships[0].user.data.id AS id_user,
    attributes.external_id AS id_external,
    attributes.url AS url_degrees,
    attributes.image_url AS url_image,
    attributes.title,
    attributes.college,
    attributes.degree,
    attributes.country,
    CAST(attributes.grade_point_average AS DECIMAL(10, 2)) AS grade_point_average,
    TO_DATE(attributes.graduated_at) AS dt_graduated,
    TO_TIMESTAMP(attributes.created_at) AS ts_created,
    NOW() AS ts_load
FROM
    datalake_degreed_raw.degrees