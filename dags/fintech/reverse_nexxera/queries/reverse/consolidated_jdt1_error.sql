SELECT
    CAST(`OK` AS STRING) AS OK,
    CAST(`BANK_OK` AS STRING) AS BANK_OK,
    `BANK_DIFF`AS BANK_DIFF,
    CAST(`BALANCE_OK` AS STRING) AS BALANCE_OK,
    `BALANCE_DIFF` AS BALANCE_DIFF,
    EC,
    STORE_ID,
    CAST(JdtNum AS STRING) AS ParentKey,
    CAST(LineNum AS STRING) AS LineNum,
    CAST(ShortName AS STRING) AS ShortName,
    CAST(Debit AS STRING) AS Debit,
    CAST(Credit AS STRING) AS Credit,
    CAST(BPLID AS STRING) AS BPLID,
    CAST(Reference1 AS STRING) AS Reference1,
    CAST(Reference2_ AS STRING) AS Reference2,
    CAST(AdditionalReference AS STRING) AS AdditionalReference,
    CAST(U_FinanceEntityEntryId AS STRING) AS U_FinanceEntityEntryId,
    CAST(CostingCode AS STRING) AS CostingCode,
    CAST(CostingCode2 AS STRING) AS CostingCode2,
    CAST(DueDate_ AS STRING) AS DueDate,
    year,
    month,
    day
FROM
    datalake_nexxera.dtw_filter
WHERE
    OK = 'false'
    AND DATE_TRUNC('MONTH', ts_ingested) = ADD_MONTHS(DATE_TRUNC('MONTH', now()),-1)
