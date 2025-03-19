WITH
deduplicate_payment AS (
    SELECT
        ts_updated,
        type,
        id_installment,
        GET_JSON_OBJECT(metadata, "$.our_number") AS our_number
    FROM datalake_trato_feito_clean.payment
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_installment ORDER BY ts_created DESC) = 1
),
charges AS (
    SELECT DISTINCT
        id_installment,
        id AS id_installment_charge,
        GET_JSON_OBJECT(metadata, "$.our-number") AS our_number
    FROM datalake_trato_feito_clean.installment_charges
),
cte_pay AS (
    SELECT
        i.*,
        p.ts_updated AS ts_payment_updated,
        p.type AS payment_type,
        p.our_number,
        DATEDIFF(p.ts_updated, i.dt_due) AS ts_paid_diff
    FROM
        datalake_trato_feito_clean.installment AS i
    LEFT JOIN
        deduplicate_payment AS p
            ON p.id_installment = i.id
),
deduplicate_invoice_extra AS (
    SELECT
    a.id_external AS id_invoice_extra,
    a.id_installment
  FROM
      datalake_trato_feito_clean.accounting_installment AS a
  LEFT JOIN datalake_retsuko.invoice AS i
    ON i.id_external = a.id_external
  WHERE i.status != "canceled"
  QUALIFY ROW_NUMBER() OVER(PARTITION BY a.id_installment ORDER BY COALESCE(i.ts_payment_confirmation, i.ts_paid) DESC, i.ts_created ASC) = 1
)
SELECT
    cp.id,
    cp.id_external,
    cp.id_negotiation,
    n.id_debtor_external AS id_contract,
    COALESCE(external_index + 1, DENSE_RANK() OVER(PARTITION BY cp.id_negotiation ORDER BY cp.ts_created, cp.id_external)) AS installment_number,
    ie.id_invoice_extra,
    COALESCE(cc.our_number, cp.our_number, cp.id_external) AS our_number,
    cp.status,
    cp.payment_type,
    cp.adm_fee_amount,
    cp.installment_fee_amount,
    cp.installment_interest,
    cp.installment_costs,
    cp.installment_lawyers_fee,
    cp.credit_card_fee,
    CASE
        WHEN LOWER(c.name) LIKE "%recupera%"
            OR (LOWER(c.name) LIKE "%cyber%" AND BIGINT(n.id_collector_external) < 10000000) -- migration from recupera to cyber
            OR LOWER(c.name) = "5a-collector"
            THEN cp.debts_fee_amount
        WHEN LOWER(c.name) LIKE "%cyber%" THEN (cp.installment_interest + cp.installment_fee_amount + cp.installment_costs + cp.installment_lawyers_fee)
    END AS debts_fee_amount,
    cp.discount_amount,
    cp.total_amount,
    cp.dt_due,
    cp.ts_paid_diff as ts_paid_difference,
    cp.ts_expired,
    cp.ts_created,
    cp.ts_updated,
    cp.ts_payment_updated AS ts_paid
FROM
    cte_pay AS cp
LEFT JOIN charges AS cc
    ON cp.id_installment_charge = cc.id_installment_charge
LEFT JOIN deduplicate_invoice_extra AS ie
    ON cp.id = ie.id_installment
LEFT JOIN datalake_trato_feito_clean.negotiation AS n
    ON cp.id_negotiation = n.id
LEFT JOIN datalake_trato_feito_clean.collector AS c
    ON n.id_collector = c.id
