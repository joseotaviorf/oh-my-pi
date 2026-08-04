WITH ranked AS (
    SELECT
        CCCASENO AS id_case,
        CCACCTG AS id_contract_group,
        CCACCT AS id_contract,
        CCDTUPD AS ts_updated,
        year,
        month,
        day,
        NOW() AS ts_load,
        ROW_NUMBER() OVER(PARTITION BY CCCASENO, CCACCTG, CCACCT ORDER BY MAKE_DATE(year,month,day) DESC) AS rn
    FROM datalake_cyber_legal_raw.caseacct
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_case,
    id_contract_group,
    id_contract,
    ts_updated,
    year,
    month,
    day,
    ts_load
FROM
    ranked
WHERE
    rn = 1
