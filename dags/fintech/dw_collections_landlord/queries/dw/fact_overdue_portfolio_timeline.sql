WITH deal_deduplication AS (
    SELECT
        id_invoice_original,
        id_invoice_deal,
        due_amount_deal,
        status_deal,
        payment_status_deal,
        purpose_deal,
        dt_begin_deal,
        dt_due_deal,
        dt_paid_deal,
        dt_end_deal,
        rn_deal_order
    FROM
        dw_collections_landlord.fact_landlord_deal_installment_match
    WHERE rn_deal_order = 1
),
list_invoices_installments AS (
    SELECT DISTINCT
        id_invoice_deal
    FROM
        deal_deduplication
),
full_list_pp_invoices AS (
    SELECT
        CASE
            WHEN m.tipo_fat = 'original_invoice' THEN m.tipo_fat
            WHEN li.id_invoice_deal IS NOT NULL AND m.tipo_fat = 'deal_invoice' THEN 'embedded in original row'
            WHEN li.id_invoice_deal IS NULL AND m.tipo_fat = 'deal_invoice' THEN 'deal invoice with no-match'
            ELSE NULL
        END AS flag_deal_installment_match,
        CASE
            WHEN f.id_invoice_deal IS NOT NULL THEN TRUE
            ELSE FALSE
        END AS flag_deal_existence,
        m.id_invoice,
        m.invoice_user,
        m.id_contract,
        m.id_account,
        m.id_original_invoice_external,
        m.tipo_fat,
        m.status,
        m.payment_status,
        m.purpose,
        m.reason,
        m.country_code,
        m.list_bill_items,
        m.due_amount_adjustment,
        m.due_amount,
        m.paid_amount,
        m.balance_adm_fee,
        m.balance_between_contracts,
        m.balance_brokerage,
        m.balance_collections_deal,
        m.balance_condominium,
        m.balance_fines,
        m.balance_loss,
        m.balance_outros,
        m.balance_postponement,
        m.balance_non_protection_5a,
        m.balance_rental_antecipation,
        m.balance_rental_core,
        m.balance_repair,
        m.balance_termination_fee,
        m.balance_utilities,
        m.balance_unknown,
        m.flag_invoice_nulled_by_encontro,
        m.has_bi_between_contracts,
        m.has_bi_brokerage,
        m.has_bi_collections_deal,
        m.has_bi_condominium,
        m.has_bi_fines,
        m.has_bi_loss,
        m.has_bi_outros,
        m.has_bi_postponement,
        m.has_bi_non_protection_5a,
        m.has_bi_rental_antecipation,
        m.has_bi_rental_core,
        m.has_bi_repair,
        m.has_bi_termination_fee,
        m.has_bi_utilities,
        m.has_bi_unknown,
        m.has_bi_adm_fee,
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
        f.id_invoice_original,
        f.id_invoice_deal,
        f.due_amount_deal,
        f.status_deal,
        f.payment_status_deal,
        f.purpose_deal,
        f.dt_begin_deal,
        f.dt_due_deal,
        f.dt_paid_deal,
        f.dt_end_deal,
        f.rn_deal_order
    FROM
        dw_collections_landlord.fact_invoice_landlord_portfolio AS m
    LEFT JOIN
        deal_deduplication AS f
        ON f.id_invoice_original = m.id_invoice
    LEFT JOIN
        list_invoices_installments AS li
        ON li.id_invoice_deal = m.id_invoice
    WHERE 1=1
        AND ((m.tipo_fat = 'original_invoice')
        OR (m.tipo_fat = 'deal_invoice' AND li.id_invoice_deal IS NULL))
    ORDER BY m.dt_begin DESC
),
add_end_date_official AS (
    SELECT
        CASE
            WHEN flag_deal_existence THEN COALESCE(dt_end_deal, current_date)
            WHEN NOT(flag_deal_existence) THEN COALESCE(dt_end, current_date)
        END AS dt_ended_official,
        flag_deal_installment_match,
        flag_deal_existence,
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
        ts_retsuko_updated,
        id_invoice_original,
        id_invoice_deal,
        due_amount_deal,
        status_deal,
        payment_status_deal,
        purpose_deal,
        dt_begin_deal,
        dt_due_deal,
        dt_paid_deal,
        dt_end_deal,
        rn_deal_order
    FROM
        full_list_pp_invoices
),
days_array AS (
    SELECT
        SEQUENCE(dt_begin, LAST_DAY(dt_ended_official)) AS dt_reference_array,
        id_invoice,
        id_contract
    FROM
        add_end_date_official
),
date_range AS (
    SELECT
        id_contract,
        id_invoice,
        dt_reference
    FROM days_array
    LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
),
invoice_timeline AS (
    SELECT
        asdt.dt_reference,
        asdt.id_invoice,
        asdt.id_contract,
        rdb.dt_begin,
        rdb.dt_ended_official,
        rdb.flag_deal_existence,
        CASE
            WHEN asdt.dt_reference > rdb.dt_ended_official THEN TRUE
            ELSE FALSE
        END AS flag_days_extended_outside_invoice,
        CASE
            WHEN NOT(rdb.flag_deal_existence) AND rdb.status = 'canceled' AND asdt.dt_reference >= rdb.dt_canceled THEN 'canceled'
            WHEN NOT(rdb.flag_deal_existence) AND rdb.status IN ('paid','written-down') AND asdt.dt_reference >= rdb.dt_paid THEN rdb.status
            WHEN NOT(rdb.flag_deal_existence) AND rdb.status IN ('open') THEN 'open'
            WHEN NOT(rdb.flag_deal_existence) AND rdb.status IN ('not-payable') AND asdt.dt_reference >= rdb.dt_END THEN 'written-down-by-encontro-contas'
            WHEN NOT(rdb.flag_deal_existence) THEN 'open'
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference < rdb.dt_paid THEN 'open'
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference < rdb.dt_ended_official THEN CONCAT('deal', '-', 'open')
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference >= rdb.dt_ended_official AND rdb.status_deal <> 'not-payable' THEN CONCAT('deal', '-', rdb.status_deal)
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference >= rdb.dt_ended_official AND rdb.status_deal = 'not-payable' THEN CONCAT('deal', '-', 'written-down-by-encontro-contas')
            ELSE 'undefined'
        END AS invoice_status_timeline,
        CASE
            WHEN NOT(rdb.flag_deal_existence) THEN 'original-life'
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference < rdb.dt_paid THEN 'original-life'
            WHEN (rdb.flag_deal_existence) AND rdb.status = 'written-down' AND asdt.dt_reference >= rdb.dt_paid THEN CONCAT('deal-extended-life')
            ELSE 'undefined'
        END AS invoice_life_status_timeline,
        rdb.flag_deal_installment_match,
        rdb.tipo_fat,
        rdb.flag_invoice_nulled_by_encontro,
        rdb.due_amount_adjustment,
        rdb.invoice_user,
        rdb.id_account,
        rdb.status,
        rdb.payment_status,
        rdb.purpose,
        rdb.reason,
        rdb.country_code,
        rdb.due_amount,
        rdb.paid_amount,
        rdb.accrual_year_month,
        rdb.dt_begin,
        rdb.dt_end,
        rdb.dt_paid,
        rdb.dt_canceled,
        rdb.dt_sent,
        rdb.dt_due,
        rdb.dt_due_adjusted,
        rdb.dt_created,
        rdb.ts_retsuko_updated,
        rdb.id_original_invoice_external,
        rdb.list_bill_items,
        rdb.has_bi_adm_fee,
        rdb.has_bi_between_contracts,
        rdb.has_bi_brokerage,
        rdb.has_bi_collections_deal,
        rdb.has_bi_condominium,
        rdb.has_bi_fines,
        rdb.has_bi_loss,
        rdb.has_bi_outros,
        rdb.has_bi_postponement,
        rdb.has_bi_non_protection_5a,
        rdb.has_bi_rental_antecipation,
        rdb.has_bi_rental_core,
        rdb.has_bi_repair,
        rdb.has_bi_termination_fee,
        rdb.has_bi_utilities,
        rdb.has_bi_unknown,
        rdb.balance_adm_fee,
        rdb.balance_between_contracts,
        rdb.balance_brokerage,
        rdb.balance_collections_deal,
        rdb.balance_condominium,
        rdb.balance_fines,
        rdb.balance_loss,
        rdb.balance_outros,
        rdb.balance_postponement,
        rdb.balance_non_protection_5a,
        rdb.balance_rental_antecipation,
        rdb.balance_rental_core,
        rdb.balance_repair,
        rdb.balance_termination_fee,
        rdb.balance_utilities,
        rdb.balance_unknown,
        rdb.id_invoice_original,
        rdb.id_invoice_deal,
        rdb.due_amount_deal,
        rdb.status_deal,
        rdb.payment_status_deal,
        rdb.purpose_deal,
        rdb.dt_begin_deal,
        rdb.dt_due_deal,
        rdb.dt_paid_deal,
        rdb.dt_end_deal,
        rdb.rn_deal_order
    FROM date_range AS asdt
    LEFT JOIN
        add_end_date_official AS rdb
        ON rdb.id_invoice = asdt.id_invoice
        AND rdb.id_contract = asdt.id_contract
),
add_recovery_and_lagging AS (
    SELECT
        CASE
            WHEN LEAST(dt_reference, dt_ended_official) > dt_due THEN TRUE
            ELSE FALSE
        END AS flag_delay,
        CASE
            WHEN LEAST(dt_reference, dt_ended_official) > dt_due AND invoice_life_status_timeline = 'original-life' THEN TRUE
            WHEN LEAST(dt_reference, dt_ended_official) > dt_due_deal AND invoice_life_status_timeline <> 'original-life' THEN TRUE
            ELSE FALSE
        END AS flag_delay_t1,
        DATEDIFF(DAY, dt_due, LEAST(dt_reference, dt_ended_official)) AS delay_t2,
        dt_reference,
        id_invoice,
        id_contract,
        dt_begin,
        dt_ended_official,
        flag_deal_existence,
        flag_days_extended_outside_invoice,
        invoice_status_timeline,
        invoice_life_status_timeline,
        flag_deal_installment_match,
        tipo_fat,
        flag_invoice_nulled_by_encontro,
        due_amount_adjustment,
        invoice_user,
        id_account,
        status,
        payment_status,
        purpose,
        reason,
        country_code,
        due_amount,
        paid_amount,
        accrual_year_month,
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
        balance_unknown,
        id_invoice_original,
        id_invoice_deal,
        due_amount_deal,
        status_deal,
        payment_status_deal,
        purpose_deal,
        dt_begin_deal,
        dt_due_deal,
        dt_paid_deal,
        dt_end_deal,
        rn_deal_order,
        CASE
            WHEN invoice_status_timeline IN ('paid', 'deal-paid', 'written-down-by-encontro-contas', 'deal-written-down-by-encontro-contas') THEN due_amount_adjustment
            ELSE 0
        END AS recovered_amount,
        LAG(invoice_status_timeline, 1) OVER(PARTITION BY id_invoice ORDER BY dt_reference ASC) AS last_invoice_status_timeline
    FROM invoice_timeline AS it
    WHERE 1=1
),
aux_calendar AS (
    SELECT
        dd.date AS dt_base,
        dd.month_start AS month_begin,
        dd.month_end AS month_end,
        dd.quarter AS quarter,
        dd.year AS ano,
        dd.working_days_in_month_fintech AS business_day,
        CASE
            WHEN dd.total_working_days_in_month_fintech <= am.business_day AND dd.total_working_days_in_month_fintech = dd.working_days_in_month_fintech THEN 'atual'
            WHEN dd.working_days_in_month_fintech < am.business_day THEN 'passado'
            WHEN dd.working_days_in_month_fintech = am.business_day THEN 'atual'
            ELSE 'futuro'
        END AS class_business_day,
        COALESCE(amdu.max_dt_business_day IS NOT NULL, FALSE) AS is_ultima_dt_du,
        (dd.date = dd.month_end OR dd.date = DATE_ADD(CURRENT_DATE(), -1)) AS is_full_month,
        dd.is_brz_fintech_holiday AS feriado,
        dd.weekEND AS fim_de_semana
    FROM
        dw_public.dim_date AS dd
    CROSS JOIN (
        SELECT dd.working_days_in_month_fintech AS business_day
        FROM dw_public.dim_date AS dd
        WHERE dd.date = DATE_ADD(CURRENT_DATE(), -1)
    ) AS am
    LEFT JOIN (
        SELECT
            MAX(dd.date) AS max_dt_business_day,
            dd.month_start
        FROM dw_public.dim_date AS dd
        WHERE dd.date BETWEEN ADD_MONTHS(TRUNC(CURRENT_DATE(), 'MM'), -24) AND DATE_ADD(CURRENT_DATE(), -1)
        GROUP BY dd.month_start, dd.working_days_in_month_fintech
    ) AS amdu ON amdu.max_dt_business_day = dd.date AND amdu.month_start = dd.month_start
),
contract_level_delay AS (
    SELECT
        dt_reference,
        id_contract,
        MAX(delay_t2) AS max_delay_t2_contract_level
    FROM add_recovery_and_lagging
    GROUP BY 1,2
),
add_aux_calendar AS (
    SELECT
        m.flag_delay,
        m.flag_delay_t1,
        m.delay_t2,
        m.dt_reference,
        m.id_invoice,
        m.id_contract,
        m.dt_begin,
        m.dt_ended_official,
        m.flag_deal_existence,
        m.flag_days_extended_outside_invoice,
        m.invoice_status_timeline,
        m.invoice_life_status_timeline,
        m.flag_deal_installment_match,
        m.tipo_fat,
        m.flag_invoice_nulled_by_encontro,
        m.due_amount_adjustment,
        m.invoice_user,
        m.id_account,
        m.status,
        m.payment_status,
        m.purpose,
        m.reason,
        m.country_code,
        m.due_amount,
        m.paid_amount,
        m.accrual_year_month,
        m.dt_end,
        m.dt_paid,
        m.dt_canceled,
        m.dt_sent,
        m.dt_due,
        m.dt_due_adjusted,
        m.dt_created,
        m.ts_retsuko_updated,
        m.id_original_invoice_external,
        m.list_bill_items,
        m.has_bi_adm_fee,
        m.has_bi_between_contracts,
        m.has_bi_brokerage,
        m.has_bi_collections_deal,
        m.has_bi_condominium,
        m.has_bi_fines,
        m.has_bi_loss,
        m.has_bi_outros,
        m.has_bi_postponement,
        m.has_bi_non_protection_5a,
        m.has_bi_rental_antecipation,
        m.has_bi_rental_core,
        m.has_bi_repair,
        m.has_bi_termination_fee,
        m.has_bi_utilities,
        m.has_bi_unknown,
        m.balance_adm_fee,
        m.balance_between_contracts,
        m.balance_brokerage,
        m.balance_collections_deal,
        m.balance_condominium,
        m.balance_fines,
        m.balance_loss,
        m.balance_outros,
        m.balance_postponement,
        m.balance_non_protection_5a,
        m.balance_rental_antecipation,
        m.balance_rental_core,
        m.balance_repair,
        m.balance_termination_fee,
        m.balance_utilities,
        m.balance_unknown,
        m.id_invoice_original,
        m.id_invoice_deal,
        m.due_amount_deal,
        m.status_deal,
        m.payment_status_deal,
        m.purpose_deal,
        m.dt_begin_deal,
        m.dt_due_deal,
        m.dt_paid_deal,
        m.dt_end_deal,
        m.rn_deal_order,
        m.recovered_amount,
        m.last_invoice_status_timeline,
        f.month_end,
        COALESCE(g.max_delay_t2_contract_level, 0) AS max_delay_t2_contract_level,
        CASE
            WHEN COALESCE(g.max_delay_t2_contract_level, 0) <= 0 THEN 'Current'
            WHEN COALESCE(g.max_delay_t2_contract_level, 0) <= 30 THEN '1-30'
            WHEN COALESCE(g.max_delay_t2_contract_level, 0) <= 60 THEN '31-60'
            WHEN COALESCE(g.max_delay_t2_contract_level, 0) <= 90 THEN '61-90'
            ELSE '90+' END AS delay_range_contract_t2
    FROM
        add_recovery_and_lagging AS m
    LEFT JOIN
        aux_calendar AS f
        ON f.dt_base = m.dt_reference
    LEFT JOIN
        contract_level_delay AS g
        ON g.dt_reference = m.dt_reference
        AND g.id_contract = m.id_contract
)
SELECT
    CONCAT(id_invoice, id_contract, DATE_FORMAT(dt_reference, 'yyyyMMdd')) AS sk_overdue_portfolio_timeline,
    id_invoice,
    id_contract,
    id_account,
    id_original_invoice_external,
    id_invoice_original,
    id_invoice_deal,
    country_code,
    rn_deal_order,
    list_bill_items,
    invoice_user,
    invoice_status_timeline,
    invoice_life_status_timeline,
    delay_t2,
    tipo_fat,
    status,
    max_delay_t2_contract_level,
    delay_range_contract_t2,
    last_invoice_status_timeline,
    payment_status,
    purpose,
    reason,
    status_deal,
    payment_status_deal,
    purpose_deal,
    due_amount,
    due_amount_adjustment,
    due_amount_deal,
    recovered_amount,
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
    flag_delay,
    flag_delay_t1,
    flag_deal_existence,
    flag_days_extended_outside_invoice,
    flag_deal_installment_match,
    flag_invoice_nulled_by_encontro,
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
    accrual_year_month,
    month_end,
    dt_reference,
    dt_begin,
    dt_ended_official,
    dt_end,
    dt_paid,
    dt_canceled,
    dt_sent,
    dt_due,
    dt_due_adjusted,
    dt_created,
    dt_begin_deal AS dt_began_deal,
    dt_due_deal,
    dt_paid_deal,
    dt_end_deal AS dt_ended_deal,
    ts_retsuko_updated,
    LAST_VALUE(CASE WHEN dt_reference = month_end THEN max_delay_t2_contract_level ELSE NULL END, TRUE) OVER(PARTITION BY id_invoice ORDER BY dt_reference ASC) AS last_contract_delay_at_closing
 FROM
    add_aux_calendar
