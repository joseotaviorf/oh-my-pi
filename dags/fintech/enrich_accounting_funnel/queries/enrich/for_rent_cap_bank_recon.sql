WITH francesinha AS (
    SELECT
        UPPER(CASE
            WHEN company_use RLIKE '[0-9]P[0-9]' AND LENGTH(TRIM(company_use)) = 11 AND SUBSTRING(company_use, 1, 1) = '0' THEN SUBSTRING(REGEXP_REPLACE(SUBSTRING(REPLACE(company_use, '|', '!'), 1, LENGTH(company_use) - 2), 'P.', 'P'), 2, LENGTH(company_use))
            WHEN company_use RLIKE '[0-9]P[0-9]' THEN REGEXP_REPLACE(SUBSTRING(REPLACE(company_use, '|', '!'), 1, LENGTH(company_use) - 2), 'P.', 'P')
            ELSE REPLACE(company_use, '|', '!')
        END) AS company_use,
        our_number,
        bank_account,
        dt_paid,
        occurrence_code AS last_occurrence_code,
        IF(occurrence_code = '00', paid_amount, 0.00) AS paid_amount
    FROM
        datalake_nexxera.cnab_payments
    WHERE
        occurrence_code IN ('00', 'DV')
    AND
        is_latest_attempt IS TRUE
    AND
        bank_account IN (426887, 79952, 433065, 502307)
),

sap AS (
    SELECT
        UPPER(id_external_payment) AS company_use,
        account_number,
        dt_reference AS dt_paid,
        dt_tax,
        ROUND(SUM(debit_credit), 2) AS paid_amount
    FROM
        datalake_pas.ledger
    WHERE
        account_number IN ('11102.01.04', '11102.02.01', '11102.01.08', '11102.01.07')
    GROUP BY
        1, 2, 3, 4
),

cap_sap AS (
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        sap
    UNION ALL
    SELECT DISTINCT
        company_use,
        dt_paid
    FROM
        francesinha
)

SELECT DISTINCT
    cs.company_use AS id_company_use,
    f.bank_account AS id_bank_account,
    f.last_occurrence_code,
    f.paid_amount AS bank_paid_amount,
    sap.paid_amount AS sap_paid_amount,
    CASE
        WHEN (ABS(f.paid_amount) = ABS(sap.paid_amount)) THEN TRUE
        WHEN last_occurrence_code = 'DV' AND (sap.paid_amount = 0 OR sap.paid_amount IS NULL) THEN TRUE
    ELSE FALSE
    END AS is_reconcilied,
    f.dt_paid AS dt_bank_paid,
    sap.dt_paid AS dt_sap_paid,
    sap.dt_tax AS dt_sap_tax,
    cs.dt_paid
FROM
    cap_sap cs
LEFT JOIN
    francesinha f
        ON f.company_use = cs.company_use
        AND cs.dt_paid = f.dt_paid
LEFT JOIN
    sap
        ON cs.company_use = sap.company_use
        AND cs.dt_paid = sap.dt_paid
WHERE
    cs.company_use IS NOT NULL
    AND cs.dt_paid >= '2024-01-01'
