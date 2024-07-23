SELECT
    id,
    agent_id as id_agent,
    contract_id as id_contract,
    fee,
    month,
    year,
    created_at as ts_created,
    updated_at as ts_updated
FROM
    datalake_fastforward_homolog_raw.real_estate_agent_fee
