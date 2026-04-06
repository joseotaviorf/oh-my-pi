SELECT
    id AS id_assessment_detail,
    assessment_id AS id_assessment,
    type,
    attribute,
    value,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_inspection_services_raw.assessment_details
