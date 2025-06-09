SELECT
    id AS id_inspection_key_retrieval_confirmation,
    contract_id AS id_contract,
    inspection_id AS id_inspection,
    owner_key_location_type,
    inspector_key_location_type,
    details,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_klefki_test_raw.inspection_key_retrieval_confirmation
