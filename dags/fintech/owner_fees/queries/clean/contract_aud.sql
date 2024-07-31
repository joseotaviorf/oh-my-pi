SELECT
    id AS id_contract,
    house_id AS id_house,
    external_id AS id_external,
    admin_fee_option_id AS id_admin_fee_option,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    CAST(real_state_agent_share AS FLOAT) AS real_state_agent_share,
    CAST(rent AS FLOAT) AS rent,
    validity_date AS dt_validity,
    created_at AS ts_updated,
    updated_at AS ts_created
FROM
    datalake_owner_fees_raw.contract_aud
