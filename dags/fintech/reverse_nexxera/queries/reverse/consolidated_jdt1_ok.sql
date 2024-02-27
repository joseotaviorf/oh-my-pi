SELECT
    CAST(JdtNum AS STRING) AS ParentKey,
    CAST(LineNum AS STRING) AS LineNum,
    CAST(ShortName AS STRING) AS ShortName,
    CAST(Debit AS STRING) AS Debit,
    CAST(Credit AS STRING) AS Credit,
    CAST(BPLID AS STRING) AS BPLID,
    CAST(Reference1 AS STRING) AS Reference1,
    CAST(Reference2_ AS STRING) AS Reference2,
    MAX(AdditionalReference) AS AdditionalReference,
    CAST(U_FinanceEntityEntryId AS STRING) AS U_FinanceEntityEntryId,
    CAST(CostingCode AS STRING) AS CostingCode,
    CAST(CostingCode2 AS STRING) AS CostingCode2,
    MAX(DueDate_) AS DueDate,
    year,
    month,
    day
FROM
    datalake_nexxera.dtw_filter
WHERE
    OK = 'true'
    AND DATE_TRUNC('MONTH', ts_ingested) = ADD_MONTHS(DATE_TRUNC('MONTH', now()),-1)
GROUP BY
1,2,3,4,5,6,7,8,10,11,12,14,15,16
