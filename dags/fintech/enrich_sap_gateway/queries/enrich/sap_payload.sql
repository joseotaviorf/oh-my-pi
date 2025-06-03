WITH base AS (
    SELECT DISTINCT
        id_sync_sap_job,
        id_feature,
        id_consolidated,
        hash,
        from_json(sap_payload, 'STRUCT<DueDate: STRING, JournalEntryLines: ARRAY<STRUCT<AdditionalReference: BIGINT, BPLID: BIGINT, CostingCode: STRING, CostingCode2: STRING, Credit: STRING, Debit: STRING, Reference1: STRING, Reference2: STRING, ShortName: STRING, U_AccountingRule: STRING, U_AccountingType: STRING, U_FinanceEntityEntryId: STRING, U_UserType: STRING>>, Memo: STRING, Reference: STRING, Reference2: STRING, Reference3: BIGINT, ReferenceDate: STRING, TaxDate: STRING, U_ExternalPaymentId: STRING, U_SourceClient: STRING>') AS sap_payload  
    FROM
        datalake_sap_gateway_clean.sync_sap_job 
    WHERE
        erp_solution = 'S4'
)

SELECT  
    id_sync_sap_job,
    id_feature,
    id_consolidated,
    hash,
    sap_payload.Reference AS id_business_entity,
    sap_payload.Reference2 AS id_finance_entity,
    sap_payload.U_ExternalPaymentId AS id_external_payment,
    sap_payload.Memo AS memo,
    sap_payload.U_SourceClient AS source_client,
    sap_payload.Reference3 AS accrual_year_month,
    sap_payload.DueDate AS ts_due,
    sap_payload.TaxDate AS ts_tax,
    sap_payload.ReferenceDate AS ts_reference
FROM
    base