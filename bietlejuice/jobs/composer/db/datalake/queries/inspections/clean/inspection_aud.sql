SELECT
    id,
    client_side_id AS id_client_side,
    contract_id AS id_contract,
    external_id AS id_external,
    inspector_id AS id_inspector,
    schedule_id AS id_schedule,
    rev,
    revtype AS rev_type,
    status,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.inspection_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}