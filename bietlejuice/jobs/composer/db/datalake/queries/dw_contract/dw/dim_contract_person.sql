SELECT
    oc.id_contract_person AS sk_contract_person,
    oc.full_name,
    oc.phone_number,
    oc.email,
    cp.personal_document,
    cp.personal_document_type,
    oc.has_ongoing_contract,   
    cp.gender,
    cp.marital_status,
    cp.state_code,
    cp.dt_birth,
    cp.ts_created,
    cp.ts_updated,
    NOW() AS ts_load
FROM
    datalake_ebdb_contract.ongoing_contracts AS oc
    LEFT JOIN
        datalake_ebdb_contract.contract_person AS cp
            ON cp.id_contract_person = oc.id_contract_person