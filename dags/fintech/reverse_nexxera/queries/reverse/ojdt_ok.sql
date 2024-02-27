SELECT
    CAST(JdtNum AS STRING) AS JdtNum,
    CAST(ReferenceDate AS STRING) AS ReferenceDate,
    MAX(Duedate) as DueDate,
    CAST(TaxDate AS STRING) AS TaxDate,
    CAST(Reference AS STRING) AS Reference,
    CAST(Reference2 AS STRING) AS Reference2,
    MAX(Reference3) as Reference3,
    CAST(Memo AS STRING) AS Memo,
    CAST(U_ExternalPaymentId AS STRING) AS U_ExternalPaymentId,
    CAST(U_SourceClient AS STRING)AS U_SourceClient,
    CAST(U_RSD_UUIDSB AS STRING) AS U_RSD_UUIDSB,
    year,
    month,
    day
FROM
    datalake_nexxera.dtw_filter
WHERE
    1=1
    AND OK = 'true'
    AND shortname = '11102.01.09'
    AND CAST(ts_ingested AS DATE) = (CAST(NOW() AS DATE) - 1)
GROUP BY
1,2,4,5,6,8,9,10,11,12,13,14
