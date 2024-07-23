SELECT
    id as id_real_estate_agent_fee,
    agent_id as id_agent,
    contract_id as id_contract,
    rev,
    revend as rev_end,
    fee,
    month,
    year
FROM
    datalake_fastforward_homolog_raw.real_estate_agent_fee_aud
