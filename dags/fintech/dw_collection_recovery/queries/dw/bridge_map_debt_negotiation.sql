WITH deduplicate_creditor_pending AS (
    SELECT DISTINCT
        id_creditor,
        id_contract,
        id_installment,
        installment_code
    FROM datalake_recupera_clean.creditor_pending
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment, installment_code ORDER BY dt_table_insertion DESC, ts_load DESC) = 1
),
deduplicate_complementary_records AS (
    SELECT DISTINCT
        id_creditor,
        id_contract,
        id_installment,
        installment_code
    FROM datalake_recupera_clean.complementary_records
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_last_debt_update DESC) = 1
),
debts AS (
    SELECT
        COALESCE(cp.id_installment, cr.id_installment) AS id_invoice,
        COALESCE(cp.id_creditor, cr.id_creditor) AS id_creditor,
        COALESCE(cp.id_contract, cr.id_contract) AS id_contract,
        cp.installment_code AS id_negotiation_recupera
    FROM deduplicate_creditor_pending AS cp
    FULL OUTER JOIN deduplicate_complementary_records AS cr
        ON cp.id_contract = cr.id_contract
        AND cp.id_installment  = cr.id_installment
    WHERE
        cp.installment_code IS NOT NULL
)

SELECT DISTINCT
    CONCAT(id_creditor, "-", id_contract, "-", id_invoice) AS sk_debt,
    id_negotiation_recupera AS sk_negotiation,
    NOW() AS ts_load
FROM debts AS
