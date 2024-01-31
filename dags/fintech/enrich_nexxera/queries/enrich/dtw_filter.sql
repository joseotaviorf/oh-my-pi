SELECT
    `OK`,
    `BANK_OK`,
    `BANK_DIFF`,
    `BALANCE_OK`,
    `BALANCE_DIFF`,
    EC,
    STORE_ID,
    JdtNum,
    CASE
        WHEN CAST((CAST(NOW() AS DATE) - CAST(TaxDate AS DATE)) AS INT) <=  6 AND CAST((CAST(NOW() AS DATE) - CAST(TaxDate AS DATE)) AS INT) >= 0 THEN TaxDate
        WHEN YEAR(NOW()) = YEAR(TaxDate) AND MONTH(NOW()) = MONTH(TaxDate) THEN TaxDate
        ELSE CAST(NOW() AS DATE)
    END AS ReferenceDate,
    DueDate,
    TaxDate,
    Reference,
    Reference2,
    Reference3,
    Memo,
    U_ExternalPaymentId,
    U_SourceClient,
    U_RSD_UUIDSB,
    ParentKey,
    LineNum,
    ShortName,
    Debit,
    Credit,
    BPLID,
    Reference1,
    Reference2_,
    AdditionalReference,
    U_FinanceEntityEntryId,
    CostingCode,
    CostingCode2,
    DueDate_,
    year,
    month,
    day
FROM
    datalake_nexxera.nexxera_final
