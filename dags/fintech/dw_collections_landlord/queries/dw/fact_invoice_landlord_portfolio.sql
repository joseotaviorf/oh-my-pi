WITH invoice_list AS (
    SELECT
        i.id_external AS id_invoice,
        ii.invoice_user,
        i.id_contract_external AS id_contract,
        i.id_account,
        i.status,
        i.payment_status,
        i.purpose,
        i.reason,
        i.country_code,
        i.due_amount,
        i.paid_amount,
        i.accrual_year_month,
        LEAST(LEAST(DATE(i.ts_created), COALESCE(DATE(i.ts_paid), DATE(i.ts_created))), DATE(i.ts_due)) AS dt_begin,
        CASE WHEN i.ts_paid IS NOT NULL AND i.ts_canceled IS NOT NULL THEN CAST(GREATEST(i.ts_paid, i.ts_canceled) AS DATE)
            WHEN i.ts_paid IS NOT NULL AND i.ts_canceled is NULL THEN CAST(i.ts_paid AS DATE)
            WHEN i.ts_paid is NULL AND i.ts_canceled IS NOT NULL THEN CAST(i.ts_canceled AS DATE)
            WHEN i.ts_paid is NULL AND i.ts_canceled is NULL AND status = 'not-payable' THEN CAST(i.ts_retsuko_updated AS DATE)
            WHEN i.ts_paid is NULL AND i.ts_canceled is NULL AND status = 'open' THEN NULL
            ELSE NULL end dt_end,
        CAST(i.ts_paid AS DATE) AS dt_paid,
        CAST(i.ts_canceled AS DATE) AS dt_canceled,
        CAST(i.ts_sent AS DATE) AS dt_sent,
        CAST(i.ts_due AS DATE) AS dt_due,
        i.dt_due_adjusted,
        CAST(i.ts_created AS DATE) AS dt_created,
        i.ts_retsuko_updated,
        i.id_original_invoice_external
    FROM
        datalake_retsuko.invoice AS i
    LEFT JOIN
        datalake_retsuko.invoice_info AS ii
        ON ii.id_invoice = i.id_external
    WHERE
        ii.invoice_user = 'landlord'
        AND i.due_amount <= 0
),
base_bill_items AS (
    SELECT
        b.id_invoice,
        CASE
            WHEN b.bill_item IN ('ADM-FEE-ADM-PARTNER', 'ADM-FEE-TAX-IR', 'ADM-FEE-TAX-IR-QUINTO-ANDAR', 'ADM-FEE-TAX-PCC', 'ADM-FEE-TAX-PCC-ADM-PARTNER', 'ADM-FEE-TAX-PCC-QUINTO-ANDAR') THEN 'ADM-FEE'
            WHEN b.bill_item IN ('BETWEEN-CONTRACTS') THEN 'BETWEEN-CONTRACTS'
            WHEN b.bill_item IN ('BROKERAGE-ADM-PARTNER', 'BROKERAGE-ADM-PARTNER-POSTPONED', 'BROKERAGE-COMPENSATION', 'BROKERAGE-ESTATE-AGENT', 'BROKERAGE-ESTATE-AGENT-POSTPONED', 'BROKERAGE-FEE-TAX-IR', 'BROKERAGE-FEE-TAX-IR-ADM-PARTNER', 'BROKERAGE-FEE-TAX-IR-QUINTO-ANDAR', 'BROKERAGE-FIDC', 'BROKERAGE-INSTALLMENT', 'BROKERAGE-INSTALLMENT-FEE', 'BROKERAGE-LOAN-FIDC', 'BROKERAGE-PARTNER-SELECT', 'BROKERAGE-PARTNER-SELECT-POSTPONED', 'BROKERAGE-QUINTO-ANDAR', 'BROKERAGE-QUINTO-ANDAR-POSTPONED', 'BROKERAGE-THIRD-PARTY-REAL-ESTATE') THEN 'BROKERAGE'
            WHEN b.bill_item IN ('COLLECTIONS-NEGOTIATION', 'DEBIT-NEGOTIATION') THEN 'COLLECTIONS DEAL'
            WHEN b.bill_item IN ('CONDOMINIUM-5A-PAID', 'CONDOMINIUM-DEFAULTING', 'CONDOMINIUM-FINE', 'CONDOMINIUM-RESERVES-FUNDS', 'CONDOMINIUM-RESERVES-FUNDS-5A-PAID', 'CONDOMINIUM-USAGE') THEN 'CONDOMINIUM'
            WHEN b.bill_item IN ('FINE', 'FINE-AND-INTEREST', 'PROPERTY-DAMAGE-FINE') THEN 'FINES'
            WHEN b.bill_item IN ('LOSS', 'LOSSES-FRAUD', 'LOSSES-ONG') THEN 'LOSS'
            WHEN b.bill_item IN ('ADJUSTMENT-AGREEMENT-ADM-FEE', 'ADJUSTMENT-AGREEMENT-RENTAL', 'CAMPAIGN', 'CAMPAIGN-DISCOUNT', 'CREDIT-CARD-COSTS', 'CREDIT-CARD-REVENUE', 'IGPM-ADM-FEE', 'IGPM-ADM-PARTNER-ADM-FEE', 'IGPM-RENTAL', 'INSURANCE-GUARANTEE', 'INTEREST', 'IPCA-ADM-FEE', 'IPCA-ADM-PARTNER-ADM-FEE', 'IPCA-RENTAL', 'IPTU-ADJUSTMENT', 'IVA-ADM-FEE', 'IVA-BROKERAGE-ADM-PARTNER', 'IVA-BROKERAGE-ESTATE-AGENT', 'IVA-BROKERAGE-QUINTO-ANDAR', 'LOCKIN', 'NON-RESIDENT-LANDLORD', 'OTHERS', 'PAYMENT-ADJUSTMENT', 'PAYMENT-ADJUSTMENT-CORRECTION', 'PRO-GUARANTOR-5A-INSTALLMENT', 'RENTAL-GUARANTEE-FEE-REFUND') THEN 'OUTROS'
            WHEN b.bill_item IN ('POSTPONEMENT') THEN 'POSTPONEMENT'
            WHEN b.bill_item IN ('NON-PROTECTION-5A') THEN 'NON-PROTECTION-5A'
            WHEN b.bill_item IN ('ADVANCE', 'INSTALLMENT-LRA', 'RENTAL-ANTICIPATION', 'RENTAL-ANTICIPATION-5A-PAID', 'RENTAL-ANTICIPATION-FEE') THEN 'RENTAL-ANTECIPATION'
            WHEN b.bill_item IN ('ADM-FEE', 'CONDOMINIUM', 'HOME-INSURANCE', 'IPTU', 'RENTAL') THEN 'RENTAL-CORE'
            WHEN b.bill_item IN ('IMPROVEMENT-WORK', 'REPAIR-OFFBOARDING', 'REPAIR-ONGOING', 'REPAIR-WORK', 'RESIDENTIAL-PROTECTION-5A-ACQUITTANCE', 'RESIDENTIAL-PROTECTION-5A-FUND-TRANSFER') THEN 'REPAIR'
            WHEN b.bill_item IN ('EARLY-TERMINATION-FEE', 'EARLY-TERMINATION-FEE-NON-PROTECTION') THEN 'TERMINATION-FEE'
            WHEN b.bill_item IN ('LIGHT-WATER-OR-GAS', 'UTILITIES-DEFAULTING') THEN 'UTILITIES'
            ELSE 'UNKNOWN'
        END AS cluster_name,
        b.bill_item,
        value_sign_bill_item,
        b.due_amount,
        b.accrual_year_month AS accrual_year_month_bill_item,
        b.dt_created
    FROM datalake_retsuko.bill_items AS b
    INNER JOIN
        invoice_list AS li
        ON li.id_invoice = b.id_invoice
),
get_invoices_with_balance AS (
    SELECT
        b.id_invoice,
        b.cluster_name,
        SUM(b.value_sign_bill_item) AS bill_item_cluster_balance
    FROM
        base_bill_items AS b
    GROUP BY 1,2
    HAVING bill_item_cluster_balance <> 0
),
add_bill_items_flags AS (
    SELECT
        id_invoice,
        MAX(IF(cluster_name = 'ADM-FEE', TRUE, FALSE)) AS has_bi_adm_fee,
        MAX(IF(cluster_name = 'BETWEEN-CONTRACTS', TRUE, FALSE)) AS has_bi_between_contracts,
        MAX(IF(cluster_name = 'BROKERAGE', TRUE, FALSE)) AS has_bi_brokerage,
        MAX(IF(cluster_name = 'COLLECTIONS DEAL', TRUE, FALSE)) AS has_bi_collections_deal,
        MAX(IF(cluster_name = 'CONDOMINIUM', TRUE, FALSE)) AS has_bi_condominium,
        MAX(IF(cluster_name = 'FINES', TRUE, FALSE)) AS has_bi_fines,
        MAX(IF(cluster_name = 'LOSS', TRUE, FALSE)) AS has_bi_loss,
        MAX(IF(cluster_name = 'OUTROS', TRUE, FALSE)) AS has_bi_outros,
        MAX(IF(cluster_name = 'POSTPONEMENT', TRUE, FALSE)) AS has_bi_postponement,
        MAX(IF(cluster_name = 'NON-PROTECTION-5A', TRUE, FALSE)) AS has_bi_non_protection_5a,
        MAX(IF(cluster_name = 'RENTAL-ANTECIPATION', TRUE, FALSE)) AS has_bi_rental_antecipation,
        MAX(IF(cluster_name = 'RENTAL-CORE', TRUE, FALSE)) AS has_bi_rental_core,
        MAX(IF(cluster_name = 'REPAIR', TRUE, FALSE)) AS has_bi_repair,
        MAX(IF(cluster_name = 'TERMINATION-FEE', TRUE, FALSE)) AS has_bi_termination_fee,
        MAX(IF(cluster_name = 'UTILITIES', TRUE, FALSE)) AS has_bi_utilities,
        MAX(IF(cluster_name = 'UNKNOWN', TRUE, FALSE)) AS has_bi_unknown,
        SUM(IF(cluster_name = 'ADM-FEE', bill_item_cluster_balance, 0)) AS balance_adm_fee,
        SUM(IF(cluster_name = 'BETWEEN-CONTRACTS', bill_item_cluster_balance, 0)) AS balance_between_contracts,
        SUM(IF(cluster_name = 'BROKERAGE', bill_item_cluster_balance, 0)) AS balance_brokerage,
        SUM(IF(cluster_name = 'COLLECTIONS DEAL', bill_item_cluster_balance, 0)) AS balance_collections_deal,
        SUM(IF(cluster_name = 'CONDOMINIUM', bill_item_cluster_balance, 0)) AS balance_condominium,
        SUM(IF(cluster_name = 'FINES', bill_item_cluster_balance, 0)) AS balance_fines,
        SUM(IF(cluster_name = 'LOSS', bill_item_cluster_balance, 0)) AS balance_loss,
        SUM(IF(cluster_name = 'OUTROS', bill_item_cluster_balance, 0)) AS balance_outros,
        SUM(IF(cluster_name = 'POSTPONEMENT', bill_item_cluster_balance, 0)) AS balance_postponement,
        SUM(IF(cluster_name = 'NON-PROTECTION-5A', bill_item_cluster_balance, 0)) AS balance_non_protection_5a,
        SUM(IF(cluster_name = 'RENTAL-ANTECIPATION', bill_item_cluster_balance, 0)) AS balance_rental_antecipation,
        SUM(IF(cluster_name = 'RENTAL-CORE', bill_item_cluster_balance, 0)) AS balance_rental_core,
        SUM(IF(cluster_name = 'REPAIR', bill_item_cluster_balance, 0)) AS balance_repair,
        SUM(IF(cluster_name = 'TERMINATION-FEE', bill_item_cluster_balance, 0)) AS balance_termination_fee,
        SUM(IF(cluster_name = 'UTILITIES', bill_item_cluster_balance, 0)) AS balance_utilities,
        SUM(IF(cluster_name = 'UNKNOWN', bill_item_cluster_balance, 0)) AS balance_unknown
    FROM
        get_invoices_with_balance
    GROUP BY 1
),
get_invoices_bill_item_list AS (
    SELECT
        b.id_invoice,
        ARRAY_AGG(DISTINCT b.bill_item) AS list_bill_items
    FROM
        base_bill_items AS b
    GROUP BY 1
),
unified_selected_bill_items_invoices AS (
    SELECT
        m.id_invoice,
        m.invoice_user,
        m.id_contract,
        m.id_account,
        m.status,
        m.payment_status,
        m.purpose,
        m.reason,
        m.country_code,
        m.due_amount,
        m.paid_amount,
        m.accrual_year_month,
        m.dt_begin,
        m.dt_end,
        m.dt_paid,
        m.dt_canceled,
        m.dt_sent,
        m.dt_due,
        m.dt_due_adjusted,
        m.dt_created,
        m.ts_retsuko_updated,
        m.id_original_invoice_external,
        COALESCE(b_list.list_bill_items, NULL) AS list_bill_items,
        COALESCE(f.has_bi_adm_fee, FALSE) AS has_bi_adm_fee,
        COALESCE(f.has_bi_between_contracts, FALSE) AS has_bi_between_contracts,
        COALESCE(f.has_bi_brokerage, FALSE) AS has_bi_brokerage,
        COALESCE(f.has_bi_collections_deal, FALSE) AS has_bi_collections_deal,
        COALESCE(f.has_bi_condominium, FALSE) AS has_bi_condominium,
        COALESCE(f.has_bi_fines, FALSE) AS has_bi_fines,
        COALESCE(f.has_bi_loss, FALSE) AS has_bi_loss,
        COALESCE(f.has_bi_outros, FALSE) AS has_bi_outros,
        COALESCE(f.has_bi_postponement, FALSE) AS has_bi_postponement,
        COALESCE(f.has_bi_non_protection_5a, FALSE) AS has_bi_non_protection_5a,
        COALESCE(f.has_bi_rental_antecipation, FALSE) AS has_bi_rental_antecipation,
        COALESCE(f.has_bi_rental_core, FALSE) AS has_bi_rental_core,
        COALESCE(f.has_bi_repair, FALSE) AS has_bi_repair,
        COALESCE(f.has_bi_termination_fee, FALSE) AS has_bi_termination_fee,
        COALESCE(f.has_bi_utilities, FALSE) AS has_bi_utilities,
        COALESCE(f.has_bi_unknown, FALSE) AS has_bi_unknown,
        COALESCE(f.balance_adm_fee, 0) AS balance_adm_fee,
        COALESCE(f.balance_between_contracts, 0) AS balance_between_contracts,
        COALESCE(f.balance_brokerage, 0) AS balance_brokerage,
        COALESCE(f.balance_collections_deal, 0) AS balance_collections_deal,
        COALESCE(f.balance_condominium, 0) AS balance_condominium,
        COALESCE(f.balance_fines, 0) AS balance_fines,
        COALESCE(f.balance_loss, 0) AS balance_loss,
        COALESCE(f.balance_outros, 0) AS balance_outros,
        COALESCE(f.balance_postponement, 0) AS balance_postponement,
        COALESCE(f.balance_non_protection_5a, 0) AS balance_non_protection_5a,
        COALESCE(f.balance_rental_antecipation, 0) AS balance_rental_antecipation,
        COALESCE(f.balance_rental_core, 0) AS balance_rental_core,
        COALESCE(f.balance_repair, 0) AS balance_repair,
        COALESCE(f.balance_termination_fee, 0) AS balance_termination_fee,
        COALESCE(f.balance_utilities, 0) AS balance_utilities,
        COALESCE(f.balance_unknown, 0) AS balance_unknown
    FROM
        invoice_list AS m
    LEFT JOIN
        add_bill_items_flags AS f
        ON f.id_invoice = m.id_invoice
    LEFT JOIN
        get_invoices_bill_item_list AS b_list
        ON b_list.id_invoice = m.id_invoice
),
original_flag AS (
    SELECT
        CASE
            WHEN has_bi_collections_deal AND purpose = 'extra' THEN 'deal_invoice'
            ELSE 'original_invoice'
        END AS tipo_fat,
        CASE
            WHEN due_amount = 0 AND balance_between_contracts < 0 THEN TRUE
            ELSE FALSE
        END AS flag_invoice_NULLed_by_encontro,
        CASE
            WHEN due_amount = 0 AND balance_between_contracts < 0 THEN balance_between_contracts
            ELSE due_amount
        END AS due_amount_adjustment,
        id_invoice,
        invoice_user,
        id_contract,
        id_account,
        status,
        payment_status,
        purpose,
        reason,
        country_code,
        due_amount,
        paid_amount,
        accrual_year_month,
        dt_begin,
        dt_end,
        dt_paid,
        dt_canceled,
        dt_sent,
        dt_due,
        dt_due_adjusted,
        dt_created,
        ts_retsuko_updated,
        id_original_invoice_external,
        list_bill_items,
        has_bi_adm_fee,
        has_bi_between_contracts,
        has_bi_brokerage,
        has_bi_collections_deal,
        has_bi_condominium,
        has_bi_fines,
        has_bi_loss,
        has_bi_outros,
        has_bi_postponement,
        has_bi_non_protection_5a,
        has_bi_rental_antecipation,
        has_bi_rental_core,
        has_bi_repair,
        has_bi_termination_fee,
        has_bi_utilities,
        has_bi_unknown,
        balance_adm_fee,
        balance_between_contracts,
        balance_brokerage,
        balance_collections_deal,
        balance_condominium,
        balance_fines,
        balance_loss,
        balance_outros,
        balance_postponement,
        balance_non_protection_5a,
        balance_rental_antecipation,
        balance_rental_core,
        balance_repair,
        balance_termination_fee,
        balance_utilities,
        balance_unknown
    FROM unified_selected_bill_items_invoices
)
SELECT
    id_invoice,
    invoice_user,
    id_contract,
    id_account,
    id_original_invoice_external,
    tipo_fat,
    status,
    payment_status,
    purpose,
    reason,
    country_code,
    list_bill_items,
    due_amount_adjustment,
    due_amount,
    paid_amount,
    balance_adm_fee,
    balance_between_contracts,
    balance_brokerage,
    balance_collections_deal,
    balance_condominium,
    balance_fines,
    balance_loss,
    balance_outros,
    balance_postponement,
    balance_non_protection_5a,
    balance_rental_antecipation,
    balance_rental_core,
    balance_repair,
    balance_termination_fee,
    balance_utilities,
    balance_unknown,
    flag_invoice_nulled_by_encontro,
    has_bi_between_contracts,
    has_bi_brokerage,
    has_bi_collections_deal,
    has_bi_condominium,
    has_bi_fines,
    has_bi_loss,
    has_bi_outros,
    has_bi_postponement,
    has_bi_non_protection_5a,
    has_bi_rental_antecipation,
    has_bi_rental_core,
    has_bi_repair,
    has_bi_termination_fee,
    has_bi_utilities,
    has_bi_unknown,
    has_bi_adm_fee,
    accrual_year_month,
    dt_begin,
    dt_end,
    dt_paid,
    dt_canceled,
    dt_sent,
    dt_due,
    dt_due_adjusted,
    dt_created,
    ts_retsuko_updated
FROM original_flag
WHERE 1=1
AND NOT(due_amount = 0 AND due_amount_adjustment = 0)
