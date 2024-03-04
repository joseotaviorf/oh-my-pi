WITH deduplicate_creditor_pending AS (
    SELECT DISTINCT
        id_creditor,
        id_contract,
        id_installment,
        IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
    FROM datalake_recupera_clean.creditor_pending
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY dt_table_insertion DESC, ts_load DESC) = 1
),
deduplicate_complementary_records AS (
    SELECT DISTINCT
        id_creditor,
        id_contract,
        id_installment,
        IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
    FROM datalake_recupera_clean.complementary_records
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
deduplicate_complementary_records_written_down AS (
    SELECT DISTINCT
        id_creditor,
        id_contract,
        id_installment,
        IF(ASCII(TRIM(installment_code))=0, NULL, installment_code) AS id_negotiation
    FROM datalake_recupera_clean.complementary_records_written_down
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
trato_feito AS (
    SELECT
        d.id_external AS id_invoice,
        CASE
            WHEN dd.origin = "rental_contract" AND dd.type= "tenant" THEN "1"
            WHEN dd.origin = "rental_contract" AND dd.type= "landlord" THEN "2"
            WHEN dd.origin = "velo_delinquency" AND dd.type= "tenant" THEN "5"
        END AS id_creditor,
        n.id_debtor_external AS id_contract,
        NULLIF(TRIM(n.id_collector_external), "") AS id_negotiation
    FROM datalake_trato_feito_clean.negotiation AS n
    LEFT JOIN datalake_trato_feito_clean.debt AS d
        ON d.id_negotiation = n.id
    LEFT JOIN datalake_trato_feito_clean.debtor AS dd
        ON n.id_debtor = dd.id
),
debts AS (
    SELECT
        COALESCE(t.id_invoice, cp.id_installment, cr.id_installment, crwd.id_installment) AS id_invoice,
        COALESCE(cp.id_creditor, cr.id_creditor, crwd.id_creditor, t.id_creditor) AS id_creditor,
        COALESCE(t.id_contract, cp.id_contract, cr.id_contract, crwd.id_contract) AS id_contract,
        COALESCE(t.id_negotiation, cp.id_negotiation, cr.id_negotiation, crwd.id_negotiation) AS id_negotiation_recupera
    FROM deduplicate_creditor_pending AS cp
    FULL OUTER JOIN deduplicate_complementary_records AS cr
        ON cp.id_contract = cr.id_contract
        AND cp.id_installment  = cr.id_installment
        AND cp.id_negotiation = cr.id_negotiation
    FULL OUTER JOIN deduplicate_complementary_records_written_down AS crwd
        ON cp.id_contract = crwd.id_contract
        AND cp.id_installment  = crwd.id_installment
        AND cp.id_negotiation = crwd.id_negotiation
    FULL OUTER JOIN trato_feito AS t
        ON cp.id_contract = t.id_contract
        AND cp.id_installment  = t.id_invoice
        AND cp.id_negotiation = t.id_negotiation
)
SELECT DISTINCT
    CONCAT(id_creditor, "-", id_contract, "-", id_invoice) AS sk_debt,
    id_negotiation_recupera AS sk_negotiation,
    NOW() AS ts_load
FROM debts
WHERE id_negotiation_recupera IS NOT NULL
