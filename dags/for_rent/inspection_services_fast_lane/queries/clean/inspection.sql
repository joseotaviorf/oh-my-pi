SELECT
    id AS id_inspection,
    previous_inspection_id AS id_previous_inspection,
    client_side_id AS id_client_side,
    contract_id AS id_contract,
    external_id AS id_external,
    inspector_id AS id_inspector,
    schedule_id AS id_schedule,
    contract,
    house,
    schedule,
    status,
    type,
    comparative AS is_comparative,
    has_early_mediation,
    schedule_date AS ts_schedule,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspection_services_test_raw.inspection
