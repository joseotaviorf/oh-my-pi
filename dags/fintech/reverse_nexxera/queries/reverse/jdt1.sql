SELECT
    CAST(JdtNum AS STRING),
    CAST(ReferenceDate AS STRING),
    CAST(DueDate AS STRING),
    CAST(TaxDate AS STRING),
    CAST(Reference AS STRING),
    CAST(Reference2 AS STRING),
    CAST(Reference3 AS STRING),
    CAST(Memo AS STRING),
    CAST(U_ExternalPaymentId AS STRING),
    CAST(U_SourceClient AS STRING),
    CAST(U_RSD_UUIDSB AS STRING),
    CAST(ParentKey AS STRING),
    CAST(LineNum AS STRING),
    CAST(ShortName AS STRING),
    CAST(Debit AS STRING),
    CAST(Credit AS STRING),
    CAST(BPLID AS STRING),
    CAST(Reference1 AS STRING),
    CAST(Reference2_ AS STRING),
    CAST(AdditionalReference AS STRING),
    CAST(U_FinanceEntityEntryId AS STRING),
    CAST(CostingCode AS STRING),
    CAST(CostingCode2 AS STRING),
    CAST(DueDate_ AS STRING),
    CAST(YEAR(CURRENT_DATE) AS STRING) AS year,
    CAST(MONTH(CURRENT_DATE) AS STRING) AS month,
    CAST(DAY(CURRENT_DATE) AS STRING) AS day
FROM
    datalake_nexxera.dtw_filter
WHERE
    OK = 'false'
