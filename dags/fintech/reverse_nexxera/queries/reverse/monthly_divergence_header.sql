SELECT
    CAST(`OK` AS STRING) AS OK,
    CAST(`BANK_OK` AS STRING) AS BANK_OK,
    `BANK_DIFF`AS BANK_DIFF,
    CAST(`BALANCE_OK` AS STRING) AS BALANCE_OK,
    `BALANCE_DIFF` AS BALANCE_DIFF,
    EC,
    STORE_ID,
    CAST(JdtNum AS STRING) AS JdtNum,
    CAST(ReferenceDate AS STRING) AS ReferenceDate,
    CAST(DueDate AS STRING) AS DueDate,
    CAST(TaxDate AS STRING) AS TaxDate,
    CAST(Reference AS STRING) AS Reference,
    CAST(Reference2 AS STRING) AS Reference2,
    CAST(Reference3 AS STRING) AS Reference3,
    CAST(Memo AS STRING) AS Memo,
    CAST(U_ExternalPaymentId AS STRING) AS U_ExternalPaymentId,
    CAST(U_SourceClient AS STRING)AS U_SourceClient,
    CAST(U_RSD_UUIDSB AS STRING) AS U_RSD_UUIDSB,
    YEAR(CURRENT_DATE) AS year,
    MONTH(CURRENT_DATE) AS month,
    DAY(CURRENT_DATE) AS day
FROM
    datalake_nexxera.dtw_filter
WHERE
    1=1
    AND OK = 'false'
    AND shortname = '11102.01.09'
    AND DATE_TRUNC('MONTH', ts_ingested) = ADD_MONTHS(DATE_TRUNC('MONTH', now()),-1)
