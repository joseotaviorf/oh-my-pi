SELECT
    CCCASENO AS id_case,
    CCACCTG AS id_contract_group,
    CCACCT AS id_contract,
    CCDTUPD AS ts_updated,
    year,
    month,
    day,
    NOW() AS ts_load
FROM datalake_cyber_legal_homolog_raw.caseacct
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
