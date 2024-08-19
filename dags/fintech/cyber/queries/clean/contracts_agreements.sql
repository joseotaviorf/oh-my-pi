SELECT
    ADACCT AS id_contract,
    ADAHID AS id_agreement,
    CASE
        WHEN ADACCTG = "1" THEN "QuintoAndar"
        WHEN ADACCTG = "2" THEN "QuintoCred"
        ELSE ADACCTG
    END AS contract_group
FROM datalake_cyber_raw.agrdm
