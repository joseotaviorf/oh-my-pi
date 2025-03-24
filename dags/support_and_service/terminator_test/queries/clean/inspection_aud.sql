SELECT
    id,
    contract_id AS id_contract,
    rev,
    revtype as rev_type,
    revend as rev_end,
    type,
    status,
    keys_location,
    keys_location_comment,
    date AS ts_inspected,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_test_raw.inspection_aud
