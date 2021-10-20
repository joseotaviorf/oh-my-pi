SELECT
    id AS id_diligence_appointment,
    diligence_id AS id_diligence,
    appointment,
    deleted_at AS ts_deleted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.diligence_appointment
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}