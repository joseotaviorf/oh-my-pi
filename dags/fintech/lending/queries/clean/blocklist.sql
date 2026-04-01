SELECT
    id,
    contract_external_id AS id_contract_external,
    product_id AS id_product,
    blocked_at AS ts_blocked,
    unblocked_at AS ts_unblocked
FROM
    datalake_lending_raw.blocklist
