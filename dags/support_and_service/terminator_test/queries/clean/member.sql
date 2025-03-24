SELECT
    id,
    contract_id AS id_contract,
    name,
    email,
    type,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_terminator_test_raw.member
