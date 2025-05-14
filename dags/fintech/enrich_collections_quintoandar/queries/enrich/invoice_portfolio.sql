WITH
base AS (
    SELECT
        i.*,
        ii.invoice_user AS user,
        c.id_house,
        c.id_proposal,
        c.status AS contract_status,
        c.dt_termination AS dt_contract_annulled
    FROM
        datalake_retsuko.invoice AS i
    LEFT JOIN
        datalake_retsuko.invoice_info AS ii
            ON i.id_external = ii.id_invoice
    LEFT JOIN
        datalake_ebdb_contract.contract AS c
            ON c.id = i.id_contract_external
    WHERE
        i.due_amount < 0
        AND c.country_code = 'BR'
        AND ii.invoice_user = 'tenant'
),
contract_write_off AS (
    SELECT DISTINCT
        id_contract_external
    FROM base
    WHERE is_write_off IS TRUE
),
first_payment AS (
    SELECT
        id_contract_external,
        id_external,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id_contract_external ORDER BY dt_due_adjusted, ts_created, id_external) = 1
                THEN TRUE
            ELSE FALSE
        END AS is_first_payment
    FROM base
    WHERE
        LOWER(status) != 'canceled'
        AND LOWER(contract_status) != 'cancelado'
)
SELECT
    b.id_external AS id_invoice,
    b.id AS id_invoice_internal,
    b.id_original_invoice_external,
    b.id_contract_external AS id_contract,
    b.id_contract AS id_contract_internal,
    b.id_account,
    b.id_audit,
    b.id_checkout_order,
    b.id_checkout_charge,
    b.id_idempotency,
    b.id_proposal,
    b.id_house,
    b.user,
    b.status AS invoice_status,
    b.contract_status,
    b.payment_status,
    b.substatus,
    b.negotiation_status,
    b.paid_via,
    b.purpose,
    b.closing_mode,
    b.reason,
    b.country_code,
    b.due_amount,
    b.paid_amount,
    b.payment_paid_interest_amount,
    b.payment_paid_fine_amount,
    b.accrual_year_month,
    IFNULL(b.is_write_off, FALSE) AS is_write_off,
    IF(cwo.id_contract_external IS NOT NULL, TRUE, FALSE) AS is_contract_write_off,
    fp.is_first_payment,
    b.dt_due_adjusted,
    b.dt_contract_annulled,
    b.ts_write_off,
    b.ts_paid,
    b.ts_payment_confirmation,
    b.ts_payment_event,
    b.ts_payment_divergent_fixed,
    b.ts_payment_processing,
    b.ts_payment_credit,
    b.ts_payment_chargeback,
    b.ts_payment_refunded,
    b.ts_canceled,
    b.ts_sent,
    b.ts_due,
    b.ts_nf_requested,
    b.ts_created,
    b.ts_synced,
    b.ts_retsuko_updated
FROM base AS b
LEFT JOIN contract_write_off AS cwo
    ON cwo.id_contract_external = b.id_contract_external
LEFT JOIN first_payment AS fp
    ON fp.id_external = b.id_external
        AND fp.id_contract_external = b.id_contract_external
