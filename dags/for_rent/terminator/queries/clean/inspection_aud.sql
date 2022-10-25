SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    contract_id AS id_contract,
    type,
    status,
    date AS ts_inspected,
    created_at AS ts_created,
    updated_at AS ts_updated,
    keys_location,
    keys_location_comment
FROM
    datalake_terminator_raw.inspection_aud
