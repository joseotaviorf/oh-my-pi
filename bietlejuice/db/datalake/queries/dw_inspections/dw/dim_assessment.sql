SELECT
    id_assessment AS sk_assessment,
    source,
    house_supplies,
    key_location,
    key_location_details,
    dt_revision_limit,
    ts_created,
    ts_finished,
    ts_started,
    ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_inspections_clean.assessment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}