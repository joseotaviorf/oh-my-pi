SELECT
    id AS id_assessment,
    inspection_id AS id_inspection,
    previous_assessment_id AS id_previous_assessment,
    key_location,
    key_location_details,
    source,
    house_supplies,
    limit_revision_date AS dt_revision_limit,
    created_at AS ts_created,
    finished_at AS ts_finished,
    started_at AS ts_started,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.assessment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}