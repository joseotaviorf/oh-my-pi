SELECT
    id,
    contract_id AS id_contract,
    schedule_id AS id_schedule,
    last_event_handled_date as id_last_event_handled_date,
    uuid,
    type,
    status,
    keys_location,
    keys_location_comment,
    expiration_date AS ts_expiration,
    date AS ts_inspected,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_test_raw.inspection
