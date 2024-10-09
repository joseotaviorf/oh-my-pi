SELECT
    ADACCT AS id_contract,
    ADAHID AS id_agreement,
    ADACCTG AS contract_group,
    CASE
        WHEN ADACCTG = "1" THEN "QuintoAndar"
        WHEN ADACCTG = "2" THEN "QuintoCred"
        ELSE ADACCTG
    END AS creditor,
    NOW() AS ts_load
FROM datalake_cyber_raw.agrdm
