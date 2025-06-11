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
negotiation_child AS (
    SELECT
        dn.id_invoice AS id_invoice,
        dn.id_negotiation AS id_negotiation_child,
        n.advisory AS agency,
        n.origin_agreement,
        n.dt_promisse
    FROM
        datalake_collections_quintoandar.debt_negotiated AS dn
    LEFT JOIN
        datalake_collections_quintoandar.negotiation AS n
            ON dn.id_negotiation = n.id_negotiation
                AND dn.id_contract = n.id_contract
    WHERE
        n.dt_down_payment IS NOT NULL
        AND n.negotiation_status IN ('offset', 'finished', 'broken-requested-by-client', 'broken')
    QUALIFY ROW_NUMBER() OVER(PARTITION BY dn.id_invoice ORDER BY n.dt_promisse DESC) = 1
),
negotiation_parent AS (
    SELECT
        ni.id_invoice_extra AS id_invoice,
        d.id_invoice AS id_invoice_parent,
        ni.id_negotiation AS id_negotiation_parent,
        ni.installment_number,
        DATE(i.ts_due) AS dt_due_parent,
        i.dt_due_adjusted AS dt_due_adjusted_parent,
        n.dt_promisse
    FROM
        datalake_collections_quintoandar.installment AS ni
    LEFT JOIN
        datalake_collections_quintoandar.negotiation AS n
            ON ni.id_negotiation = n.id_negotiation
                AND ni.id_contract = n.id_contract
    LEFT JOIN
        datalake_collections_quintoandar.debt_negotiated AS d
            ON d.id_negotiation = ni.id_negotiation
                AND d.id_contract = ni.id_contract
    LEFT JOIN
        datalake_retsuko.invoice AS i
            ON d.id_invoice = i.id_external
                AND d.id_contract = i.id_contract_external
    QUALIFY ROW_NUMBER() OVER(PARTITION BY ni.id_invoice_extra ORDER BY DATE(i.ts_due), ni.id_invoice_extra) = 1
),
base_negotiation AS (
    SELECT DISTINCT
        i.id_contract_external AS id_contract,
        i.id_external AS id_invoice,
        parent.id_invoice_parent,
        parent.id_negotiation_parent,
        child.id_negotiation_child,
        child.agency AS child_negotiation_agency,
        child.origin_agreement,
        parent.installment_number AS negotiation_installment_number,
        DATE(i.ts_due) AS dt_due,
        parent.dt_due_parent,
        parent.dt_due_adjusted_parent,
        parent.dt_promisse AS dt_created_negotiation_parent,
        child.dt_promisse AS dt_created_negotiation_child
    FROM
        base AS i
    LEFT JOIN
        negotiation_parent AS parent
            ON i.id_external = parent.id_invoice
    LEFT JOIN
        negotiation_child AS child
            ON child.id_invoice  = i.id_external
    WHERE
        parent.id_negotiation_parent IS NOT NULL
            OR child.id_negotiation_child IS NOT NULL
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
),
paid_by_ssn AS (
    SELECT
        id_contract,
        id_invoice,
        MAX(ts_event) AS ts_event
    FROM datalake_collections_quintoandar.delinquency_app_events
    WHERE
      funnel_step = 'Overdue Self Service Action'
      AND id_contract IS NOT NULL
      AND id_invoice IS NOT NULL
    GROUP BY 1,2
)
SELECT
    b.id_external AS id_invoice,
    b.id AS id_invoice_internal,
    b.id_original_invoice_external AS id_original_invoice,
    bn.id_invoice_parent AS id_invoice_anchor,
    b.id_contract_external AS id_contract,
    b.id_contract AS id_contract_internal,
    bn.id_negotiation_parent,
    bn.id_negotiation_child,
    bn.negotiation_installment_number,
    IF(bn.id_negotiation_parent IS NOT NULL, TRUE, FALSE) AS is_child_negotiation,
    IF(bn.id_negotiation_child IS NOT NULL, TRUE, FALSE) AS has_child,
    bn.child_negotiation_agency,
    IF(ssn.id_invoice IS NOT NULL, TRUE, FALSE) AS has_app_action_event,
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
    b.purpose,
    b.reason,
    CASE
        WHEN b.status = 'canceled' THEN 'Canceled'
        WHEN b.status = 'open' THEN NULL
        WHEN b.status = 'paid'
            AND ssn.id_invoice IS NOT NULL
            AND bn.id_negotiation_parent IS NOT NULL
            THEN 'Paid Installment in App'
        WHEN b.status = 'paid'
            AND ssn.id_invoice IS NOT NULL
            AND bn.id_negotiation_parent IS NULL
            THEN 'Paid in App'
        WHEN b.status = 'paid'
            AND ssn.id_invoice IS NULL
            AND (bn.id_negotiation_parent IS NOT NULL
                OR (purpose = 'extra'
                    AND (reason LIKE '%negotiation%'
                    OR reason LIKE '%agreement%')
                ))
            THEN 'Paid Installment outside App'
         WHEN b.status = 'paid'
            AND ssn.id_invoice IS NULL
            AND bn.id_negotiation_parent IS NULL
            THEN 'Paid outside App'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NULL
            AND (b.reason IS NULL
                OR (b.reason NOT LIKE '%negotiation%'
                  AND b.reason NOT LIKE '%agreement%'))
            THEN 'Manual Written Down'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.id_negotiation_parent IS NOT NULL
            AND bn.origin_agreement = 'Portal Auto Negociação'
            THEN 'Negotiation of Installment - SSN'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.origin_agreement = 'Portal Auto Negociação'
            THEN 'Negotiation - SSN'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.origin_agreement = 'Boletagem'
            THEN 'Negotiation - Campaign'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.origin_agreement = 'Serasa Digital'
            THEN 'Negotiation - Serasa'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.origin_agreement = 'Assessoria'
            THEN 'Negotiation - Advisory'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            AND bn.origin_agreement = 'Operador Interno'
            THEN 'Negotiation - Internal Operator'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NOT NULL
            THEN 'Negotiation - Unclassified'
        WHEN b.status = 'written-down'
            AND bn.id_negotiation_child IS NULL
                AND (b.reason LIKE '%negotiation%'
                OR b.reason LIKE '%agreement%')
            THEN 'Negotiation - Not Tracked'
        ELSE 'Unknown'
    END AS recovery_channel,
    b.paid_via,
    b.closing_mode,
    b.country_code,
    b.due_amount,
    b.paid_amount,
    b.payment_paid_interest_amount,
    b.payment_paid_fine_amount,
    b.accrual_year_month,
    IFNULL(b.is_write_off, FALSE) AS is_write_off,
    IF(cwo.id_contract_external IS NOT NULL, TRUE, FALSE) AS is_contract_write_off,
    IFNULL(fp.is_first_payment, FALSE) AS is_first_payment,
    b.dt_due_adjusted,
    bn.dt_due_parent AS dt_invoice_anchor,
    bn.dt_due_adjusted_parent AS dt_adjusted_invoice_anchor,
    b.dt_contract_annulled,
    bn.dt_created_negotiation_parent,
    bn.dt_created_negotiation_child,
    ssn.ts_event AS ts_last_app_action_event,
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
    b.ts_retsuko_updated,
    NOW() AS ts_load
FROM base AS b
LEFT JOIN contract_write_off AS cwo
    ON cwo.id_contract_external = b.id_contract_external
LEFT JOIN first_payment AS fp
    ON fp.id_external = b.id_external
        AND fp.id_contract_external = b.id_contract_external
LEFT JOIN base_negotiation AS bn
    ON bn.id_invoice = b.id_external
        AND bn.id_contract = b.id_contract_external
LEFT JOIN paid_by_ssn AS ssn
     ON ssn.id_invoice = b.id_external
        AND ssn.id_contract = b.id_contract_external
        AND DATE(ssn.ts_event) <= DATE(b.ts_paid)
        AND DATE(ssn.ts_event) >= DATE(b.ts_paid) - INTERVAL 5 DAY
