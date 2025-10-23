SELECT
    CCCASENO AS id_case,
    CCACCTG AS id_contract_group,
    CCACCT AS id_contract,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.caseacct
