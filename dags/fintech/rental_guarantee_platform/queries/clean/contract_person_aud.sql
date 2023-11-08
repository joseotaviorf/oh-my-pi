SELECT
    id,
    contract_id AS id_contract,
    person_id AS id_person,
    version,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    contract_id_mod AS mod_id_contract,
    person_id_mod AS mod_id_person,
    created_at AS ts_created
FROM
    datalake_rental_guarantee_platform_raw.contract_person_aud
