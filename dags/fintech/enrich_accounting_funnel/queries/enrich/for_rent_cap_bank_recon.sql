WITH francesinha AS (
    SELECT
        UPPER(CASE
            WHEN company_use RLIKE '[0-9]P[0-9]' AND LENGTH(TRIM(company_use)) = 11 AND SUBSTRING(company_use, 1, 1) = '0' THEN SUBSTRING(REGEXP_REPLACE(SUBSTRING(REPLACE(company_use, '|', '!'), 1, LENGTH(company_use) - 2), 'P.', 'P'), 2, LENGTH(company_use))
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

cap AS (
    SELECT
        dt_paid,
        UPPER(CASE
            WHEN reference_1 RLIKE '[0-9]P[0-9]' AND LENGTH(TRIM(reference_1)) = 11 AND SUBSTRING(reference_1, 1, 1) = '0' THEN SUBSTRING(REGEXP_REPLACE(SUBSTRING(REPLACE(reference_1, '|', '!'), 1, LENGTH(reference_1) - 2), 'P.', 'P'), 2, LENGTH(reference_1))
            ELSE REPLACE(reference_1, '|', '!')
        END) AS company_use,
        payment_status,
        reference_3 AS payment_name,
        reference_4 AS payment_type,
        SPLIT(reference_5, ':') AS id_banking_payment,
        SUM(IF(payment_status = 'chargeback', 0, paid_amount)) AS paid_amount
    FROM
        datalake_accounting_funnel.payment_platforms
    WHERE
        payment_platform = 'vans_cap'
    AND
        payment_status IN ('paid', 'chargeback')
    GROUP BY
        1, 2, 3, 4, 5, 6
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
        cap
    UNION ALL
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
    f.bank_account AS bank_account_number,
    sap.account_number AS sap_account_number,
    f.last_occurrence_code,
    f.paid_amount AS bank_paid_amount,
    cap.paid_amount AS cap_paid_amount,
    sap.paid_amount AS sap_paid_amount,
    CASE
        WHEN payment_status = 'chargeback' AND sap.paid_amount = 0 THEN TRUE
        WHEN ABS(f.paid_amount) = ABS(cap.paid_amount) THEN TRUE
    ELSE FALSE
    END AS is_vans_compliance,
    CASE
        WHEN (ABS(f.paid_amount) = ABS(sap.paid_amount)) THEN TRUE
        WHEN last_occurrence_code = 'DV' AND (sap.paid_amount = 0 OR sap.paid_amount IS NULL) THEN TRUE
    ELSE FALSE
    END AS is_reconcilied,
    f.dt_paid AS dt_bank_paid,
    cap.dt_paid AS dt_cap_paid,
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
    cap
        ON cs.company_use = cap.company_use
        AND cs.dt_paid = cap.dt_paid
LEFT JOIN
    sap
        ON cs.company_use = sap.company_use
        AND cs.dt_paid = sap.dt_paid
WHERE
    cs.company_use IS NOT NULL
    AND cs.dt_paid >= '2024-01-01'
