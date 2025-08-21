WITH
contract_features AS (
    SELECT
        dt_reference,
        id_contract,
        MAX(CAST(has_negotiation_in_contract AS INT))  AS num_has_negotiation_in_contract,
        COUNT(CASE WHEN NOT(is_negative_eligible) AND order_invoice_wallet_risk = 1 THEN id_invoice END)  AS n_anchor_invoices_not_negativable,
        COUNT(IF(is_negative_eligible, id_invoice, NULL)) AS n_invoices_negativable,
        COUNT(IF(has_bill_item_condominio, id_invoice, NULL)) AS n_condominio_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_condominio, id_invoice, NULL)) AS n_condominio_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_condominio, ABS(balance_bill_item_condominio), 0)) AS open_condominio_balance,
        COUNT(IF(has_bill_item_multa_recisoria, id_invoice, NULL)) AS n_multa_recisoria_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_multa_recisoria, id_invoice, NULL)) AS n_multa_recisoria_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_multa_recisoria, ABS(balance_bill_item_multa_recisoria), 0)) AS open_multa_recisoria_balance,
        COUNT(IF(has_bill_item_acordo, id_invoice, NULL)) AS n_acordo_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_acordo, id_invoice, NULL)) AS n_acordo_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_acordo, ABS(balance_bill_item_acordo), 0)) AS open_acordo_balance,
        COUNT(IF(has_bill_item_rental_core, id_invoice, NULL)) AS n_rental_core_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_rental_core, id_invoice, NULL)) AS n_rental_core_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_rental_core, ABS(balance_bill_item_rental_core), 0)) AS open_rental_core_balance,
        COUNT(IF(has_bill_item_reparos, id_invoice, NULL)) AS n_reparos_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_reparos, id_invoice, NULL)) AS n_reparos_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_reparos, ABS(balance_bill_item_reparos), 0)) AS open_reparos_balance,
        COUNT(IF(has_bill_item_multas_ongoing, id_invoice, NULL)) AS n_multas_ongoing_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_multas_ongoing, id_invoice, NULL)) AS n_multas_ongoing_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_multas_ongoing, ABS(balance_bill_item_multas_ongoing), 0)) AS open_multas_ongoing_balance,
        COUNT(IF(has_bill_item_utilidades, id_invoice, NULL)) AS n_utilidades_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_utilidades, id_invoice, NULL)) AS n_utilidades_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_utilidades, ABS(balance_bill_item_utilidades), 0)) AS open_utilidades_balance,
        COUNT(IF(has_bill_item_outros, id_invoice, NULL)) AS n_outros_invoices,
        COUNT(IF(payment_status = 'open' AND has_bill_item_outros, id_invoice, NULL)) AS n_outros_open_invoices,
        SUM(IF(payment_status = 'open' AND has_bill_item_outros, ABS(balance_bill_item_outros), 0)) AS open_outros_balance,
        COUNT(CASE WHEN invoice_type IN ('monthly', 'onboarding') AND invoice_delay_t1 > 0 THEN id_invoice END)  AS n_overdue_monthlys_t1,
        COUNT(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND is_child_negotiation AND invoice_delay_t1 > 0 THEN id_invoice END)  AS n_overdue_deals_t1,
        COUNT(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND NOT is_child_negotiation AND invoice_delay_t1 > 0 THEN id_invoice END)  AS n_overdue_others_t1,
        COUNT(CASE WHEN invoice_type IN ('monthly', 'onboarding') AND invoice_delay_t2 > 0 THEN id_invoice END)  AS n_overdue_monthlys_t2,
        COUNT(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND is_child_negotiation AND invoice_delay_t2 > 0 THEN id_invoice END)  AS n_overdue_deals_t2,
        COUNT(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND NOT is_child_negotiation AND invoice_delay_t2 > 0 THEN id_invoice END)  AS n_overdue_others_t2,
        SUM(CASE WHEN invoice_type IN ('monthly', 'onboarding') AND invoice_delay_t2 > 0 THEN ABS(due_amount) ELSE 0 END)  AS sum_overdue_monthlys_t2,
        SUM(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND is_child_negotiation AND invoice_delay_t2 > 0 THEN ABS(due_amount) ELSE 0 END)  AS sum_overdue_deals_t2,
        SUM(CASE WHEN invoice_type NOT IN ('monthly', 'onboarding') AND NOT is_child_negotiation AND invoice_delay_t2 > 0 THEN ABS(due_amount) ELSE 0 END)  AS sum_overdue_others_t2,
        MAX(IF(NOT is_child_negotiation, invoice_delay_t1, 0)) AS max_delay_original_invoices_t1,
        MAX(IF(is_child_negotiation, invoice_delay_t1, 0)) AS max_delay_deal_invoices_t1,
        MAX(IF(NOT is_child_negotiation, invoice_delay_t2, 0)) AS max_delay_original_invoices_t2,
        MAX(IF(is_child_negotiation, invoice_delay_t2, 0)) AS max_delay_deal_invoices_t2,
        MAX(invoice_delay_t2) AS max_delay_contaminated_contract_t2,
        MAX(contract_delay_t3_losses) AS max_delay_contaminated_contract_t3_losses,
        MAX(invoice_delay_t1) AS max_delay_contaminated_contract_t1,
        MAX(IF(payment_status = 'open', invoice_delay_t2, 0)) AS max_open_delay_contaminated_contract_t2,
        MAX(IF(payment_status = 'open', contract_delay_t3_losses, 0)) AS max_open_delay_contaminated_contract_t3_losses,
        MAX(IF(payment_status = 'open', invoice_delay_t1, 0)) AS max_open_delay_contaminated_contract_t1,
        SUM(IF(payment_status = 'open', ABS(due_amount), 0)) AS open_wallet,
        SUM(ABS(due_amount)) AS wallet,
        SUM(recovered_amount) AS recovered_amount,
        SUM(IF(NOT is_invoice_overdue_t1, ABS(due_amount), 0)) AS wallet_on_time_t1,
        SUM(IF(is_invoice_overdue_t1, ABS(due_amount), 0)) AS wallet_overdue_t1,
        SUM(IF(payment_status = 'open' AND NOT is_invoice_overdue_t1, ABS(due_amount), 0)) AS open_wallet_on_time_t1,
        SUM(IF(payment_status = 'open' AND is_invoice_overdue_t1, ABS(due_amount), 0)) AS open_wallet_overdue_t1,
        SUM(overdue_recovered_amount_t1) AS overdue_recovered_amount_t1,
        SUM(on_time_paid_amount_t1) AS on_time_paid_amount_t1,
        SUM(IF(NOT is_invoice_overdue_t2, ABS(due_amount), 0)) AS wallet_on_time_t2,
        SUM(IF(is_invoice_overdue_t2, ABS(due_amount), 0)) AS wallet_overdue_t2,
        SUM(IF(payment_status = 'open' AND NOT is_invoice_overdue_t2, ABS(due_amount), 0)) AS open_wallet_on_time_t2,
        SUM(IF(payment_status = 'open' AND is_invoice_overdue_t2, ABS(due_amount), 0)) AS open_wallet_overdue_t2,
        SUM(overdue_recovered_amount_t2) AS overdue_recovered_amount_t2,
        SUM(on_time_paid_amount_t2) AS on_time_paid_amount_t2,
        SUM(IF(NOT is_invoice_overdue_t3, ABS(due_amount), 0)) AS wallet_on_time_t3,
        SUM(IF(is_invoice_overdue_t3, ABS(due_amount), 0))  AS wallet_overdue_t3,
        SUM(IF(NOT is_invoice_overdue_t3 AND payment_status = 'open', ABS(due_amount), 0))  AS open_wallet_on_time_t3,
        SUM(IF(is_invoice_overdue_t3 AND payment_status = 'open', ABS(due_amount), 0))  AS open_wallet_overdue_t3,
        SUM(overdue_recovered_amount_t3) AS overdue_recovered_amount_t3,
        SUM(on_time_paid_amount_t3)   AS on_time_paid_amount_t3,
        SUM(CASE WHEN is_invoice_overdue_t1 AND overdue_recovered_amount_t1 > 0 AND invoice_type IN ('monthly') THEN invoice_delay_t1 ELSE 0 END) AS sum_monthly_overdue_days_paid_t1,
        COUNT(DISTINCT CASE WHEN is_invoice_overdue_t1 AND overdue_recovered_amount_t1 > 0 AND invoice_type IN ('monthly') THEN id_invoice END) AS count_monthly_overdue_invoices_paid_t1,
        COLLECT_SET(CASE
            WHEN payment_status = 'open' THEN id_invoice
            ELSE NULL
        END)  AS array_open_invoices,
        COLLECT_SET(CASE
            WHEN payment_status = 'paid' THEN id_invoice
            ELSE NULL
        END)  AS array_paid_invoices,
        COLLECT_SET(CASE
            WHEN payment_status = 'written-down' THEN id_invoice
            ELSE NULL
        END)  AS array_negotiated_invoices
    FROM dw_collections_segmentation.fact_invoice_wallet_timeline
    GROUP BY 1, 2
),
get_invoice_date_range AS (
    SELECT
        id_contract,
        dt_contract_annulled AS dt_contract_end,
        dt_contract_start,
        MIN(dt_reference) AS dt_first_invoice,
        MAX(dt_reference) AS dt_last_invoice
    FROM dw_collections_segmentation.fact_invoice_wallet_timeline
    GROUP BY 1, 2, 3
),
get_date_array AS (
    SELECT
        id_contract,
        dt_contract_end,
        dt_contract_start,
        SEQUENCE(dt_first_invoice, IF(dt_contract_end IS NOT NULL, GREATEST(DATE_ADD(dt_contract_end, 90), dt_last_invoice),
                CURRENT_DATE())) AS dt_reference_array
    FROM get_invoice_date_range
),
contract_date_references AS (
    SELECT
        id_contract,
        dt_contract_end,
        dt_contract_start,
        dt_reference
    FROM
        get_date_array
    LATERAL VIEW EXPLODE(dt_reference_array) AS dt_reference
),
invoices AS (
     SELECT
        DATE(ts_due) AS dt_pipe,
        DATE(ts_created) AS dt_invoicing,
        id_external AS id_invoice
    FROM datalake_retsuko.invoice
    WHERE purpose = 'monthly'
        AND due_amount < 0
        AND DATE(DATE_TRUNC('MONTH', ts_due)) >= DATE('2023-01-01')
),
pipeline_dates AS (
    SELECT
        DATE(DATE_TRUNC('MONTH', dt_pipe)) AS dt_month,
        dt_pipe,
        COUNT(DISTINCT id_invoice) AS invoices
    FROM invoices
    GROUP BY 1,2
),
billing_dates AS (
    SELECT
        DATE(DATE_TRUNC('MONTH', dt_invoicing)) AS dt_month,
        dt_invoicing,
        COUNT(DISTINCT id_invoice) AS invoices
    FROM invoices
    GROUP BY 1,2
),
deduplicate_pipeline_dates AS (
  SELECT *
  FROM pipeline_dates
  QUALIFY ROW_NUMBER() OVER (PARTITION BY dt_month ORDER BY invoices DESC) = 1
),
deduplicate_billing_dates AS (
  SELECT *
  FROM billing_dates
  QUALIFY ROW_NUMBER() OVER (PARTITION BY dt_month ORDER BY invoices DESC) = 1
),
get_dates_billing as (
    SELECT
        COALESCE(p.dt_month, b.dt_month) AS dt_month,
        d.month_start AS dt_month_start,
        d.month_end AS dt_month_end,
        p.dt_pipe,
        b.dt_invoicing
    FROM
        deduplicate_pipeline_dates p
    FULL OUTER JOIN
        deduplicate_billing_dates b
        ON p.dt_month = b.dt_month
    LEFT JOIN
        dw_public.dim_date AS d
            ON d.date = COALESCE(p.dt_month, b.dt_month)
),
contract_timeline AS (
    SELECT
        m.*,
        CASE
            WHEN m.dt_contract_end IS NULL
                OR m.dt_contract_end > (DATE_TRUNC('MONTH', m.dt_reference) + INTERVAL 1 MONTH) THEN 'Ativo'
            ELSE 'Finalizado'
        END AS contract_status_beginning_of_month,
        CASE
            WHEN m.dt_contract_end IS NULL
                OR m.dt_contract_end > m.dt_reference THEN 'Ativo'
            ELSE 'Finalizado'
        END AS reference_contract_status,
        m.dt_contract_start,
        m.dt_contract_end,
        d.dt_pipe,
        d.dt_month_start,
        d.dt_month_end,
        d.dt_pipe = m.dt_reference AS is_pipeturn_day,
        d.dt_month_start = m.dt_reference AS is_first_day,
        d.dt_month_end = m.dt_reference AS is_last_day,
        COALESCE(f.overdue_recovered_amount_t1, 0) > 0 AND COALESCE(f.open_wallet_overdue_t1, 0) = 0 AS is_quitacao_t1,
        COALESCE(f.overdue_recovered_amount_t2, 0) > 0 AND COALESCE(f.open_wallet_overdue_t2, 0) = 0 AS is_quitacao_t2,
        COALESCE(f.overdue_recovered_amount_t3, 0) > 0 AND COALESCE(f.open_wallet_overdue_t3, 0) = 0 AS is_quitacao_t3,
        COALESCE(f.open_wallet_overdue_t1, 0) = 0 AS is_regular_t1,
        COALESCE(f.open_wallet_overdue_t2, 0) = 0 AND COALESCE(f.overdue_recovered_amount_t2, 0) = 0 AND DATE_TRUNC('MONTH', m.dt_reference) = m.dt_reference AS is_current_at_month_start_t1,
        COALESCE(f.num_has_negotiation_in_contract, 0) AS num_has_negotiation_in_contract,
        COALESCE(f.n_anchor_invoices_not_negativable, 0) AS n_anchor_invoices_not_negativable,
        COALESCE(f.n_invoices_negativable, 0) AS n_invoices_negativable,
        COALESCE(f.n_condominio_invoices, 0) AS n_condominio_invoices,
        COALESCE(f.n_condominio_open_invoices, 0) AS n_condominio_open_invoices,
        COALESCE(f.open_condominio_balance, 0) AS open_condominio_balance,
        COALESCE(f.n_multa_recisoria_invoices, 0) AS n_multa_recisoria_invoices,
        COALESCE(f.n_multa_recisoria_open_invoices, 0)  AS n_multa_recisoria_open_invoices,
        COALESCE(f.open_multa_recisoria_balance, 0) AS open_multa_recisoria_balance,
        COALESCE(f.n_acordo_invoices, 0)  AS n_acordo_invoices,
        COALESCE(f.n_acordo_open_invoices , 0) AS n_acordo_open_invoices,
        COALESCE(f.open_acordo_balance, 0) AS open_acordo_balance,
        COALESCE(f.n_rental_core_invoices, 0) AS n_rental_core_invoices,
        COALESCE(f.n_rental_core_open_invoices, 0) AS n_rental_core_open_invoices,
        COALESCE(f.open_rental_core_balance, 0) AS open_rental_core_balance,
        COALESCE(f.n_reparos_invoices, 0) AS n_reparos_invoices,
        COALESCE(f.n_reparos_open_invoices, 0) AS n_reparos_open_invoices,
        COALESCE(f.open_reparos_balance, 0) AS open_reparos_balance,
        COALESCE(f.n_multas_ongoing_invoices, 0) AS n_multas_ongoing_invoices,
        COALESCE(f.n_multas_ongoing_open_invoices, 0) AS n_multas_ongoing_open_invoices,
        COALESCE(f.open_multas_ongoing_balance, 0) AS open_multas_ongoing_balance,
        COALESCE(f.n_utilidades_invoices,0) AS n_utilidades_invoices,
        COALESCE(f.n_utilidades_open_invoices, 0) AS n_utilidades_open_invoices,
        COALESCE(f.open_utilidades_balance,0) AS open_utilidades_balance,
        COALESCE(f.n_outros_invoices,0) AS n_outros_invoices,
        COALESCE(f.n_outros_open_invoices,0) AS n_outros_open_invoices,
        COALESCE(f.open_outros_balance,0) AS open_outros_balance,
        COALESCE(f.n_overdue_monthlys_t1,0) AS n_overdue_monthlys_t1,
        COALESCE(f.n_overdue_deals_t1,0) AS n_overdue_deals_t1,
        COALESCE(f.n_overdue_others_t1, 0) AS n_overdue_others_t1,
        COALESCE(f.n_overdue_monthlys_t2, 0) AS n_overdue_monthlys_t2,
        COALESCE(f.n_overdue_deals_t2, 0) AS n_overdue_deals_t2,
        COALESCE(f.n_overdue_others_t2, 0) AS n_overdue_others_t2,
        COALESCE(f.sum_overdue_monthlys_t2, 0) AS sum_overdue_monthlys_t2,
        COALESCE(f.sum_overdue_deals_t2, 0) AS sum_overdue_deals_t2,
        COALESCE(f.sum_overdue_others_t2, 0) AS sum_overdue_others_t2,
        COALESCE(f.max_delay_original_invoices_t1, 0) AS max_delay_original_invoices_t1,
        COALESCE(f.max_delay_deal_invoices_t1, 0) AS max_delay_deal_invoices_t1,
        COALESCE(f.max_delay_original_invoices_t2, 0) AS max_delay_original_invoices_t2,
        COALESCE(f.max_delay_deal_invoices_t2, 0) AS max_delay_deal_invoices_t2,
        COALESCE(f.max_delay_contaminated_contract_t2, 0) AS max_delay_contaminated_contract_t2,
        COALESCE(f.max_delay_contaminated_contract_t3_losses, 0) AS max_delay_contaminated_contract_t3_losses,
        COALESCE(f.max_delay_contaminated_contract_t1, 0) AS max_delay_contaminated_contract_t1,
        COALESCE(f.max_open_delay_contaminated_contract_t2, 0) AS max_open_delay_contaminated_contract_t2,
        COALESCE(f.max_open_delay_contaminated_contract_t3_losses, 0) AS max_open_delay_contaminated_contract_t3_losses,
        COALESCE(f.max_open_delay_contaminated_contract_t1, 0) AS max_open_delay_contaminated_contract_t1,
        COALESCE(f.open_wallet,0) AS open_wallet,
        COALESCE(f.wallet,0) AS wallet,
        COALESCE(f.recovered_amount,0) AS recovered_amount,
        COALESCE(f.wallet_on_time_t1,0) AS wallet_on_time_t1,
        COALESCE(f.wallet_overdue_t1, 0) AS wallet_overdue_t1,
        COALESCE(f.open_wallet_on_time_t1, 0) AS open_wallet_on_time_t1,
        COALESCE(f.open_wallet_overdue_t1, 0) AS open_wallet_overdue_t1,
        COALESCE(f.overdue_recovered_amount_t1, 0) AS overdue_recovered_amount_t1,
        COALESCE(f.on_time_paid_amount_t1, 0) AS on_time_paid_amount_t1,
        COALESCE(f.wallet_on_time_t2,0) AS wallet_on_time_t2,
        COALESCE(f.wallet_overdue_t2,0) AS wallet_overdue_t2,
        COALESCE(f.open_wallet_on_time_t2, 0) AS open_wallet_on_time_t2,
        COALESCE(f.open_wallet_overdue_t2, 0) AS open_wallet_overdue_t2,
        COALESCE(f.overdue_recovered_amount_t2, 0) AS overdue_recovered_amount_t2,
        COALESCE(f.on_time_paid_amount_t2, 0) AS on_time_paid_amount_t2,
        COALESCE(f.wallet_on_time_t3,0) AS wallet_on_time_t3,
        COALESCE(f.wallet_overdue_t3,0) AS wallet_overdue_t3,
        COALESCE(f.open_wallet_on_time_t3, 0) AS open_wallet_on_time_t3,
        COALESCE(f.open_wallet_overdue_t3, 0) AS open_wallet_overdue_t3,
        COALESCE(f.overdue_recovered_amount_t3, 0) AS overdue_recovered_amount_t3,
        COALESCE(f.on_time_paid_amount_t3, 0) AS on_time_paid_amount_t3,
        COALESCE(f.sum_monthly_overdue_days_paid_t1, 0) AS sum_monthly_overdue_days_paid_t1,
        COALESCE(f.count_monthly_overdue_invoices_paid_t1, 0) AS count_monthly_overdue_invoices_paid_t1,
        COALESCE(f.array_open_invoices, NULL) AS array_open_invoices,
        COALESCE(f.array_paid_invoices, NULL) AS array_paid_invoices,
        COALESCE(f.array_negotiated_invoices, NULL) AS array_negotiated_invoices
    FROM
        contract_date_references m
    LEFT JOIN
        contract_features f
            ON m.id_contract = f.id_contract
            AND m.dt_reference = f.dt_reference
    LEFT JOIN
        get_dates_billing d
            ON d.dt_month = DATE_TRUNC('MONTH', m.dt_reference)
),
fact_collection_base AS (
    SELECT
        DATE(dt_occurrence) AS dt_reference,
        sk_contract,
        SUM(total_esforco) AS esforco,
        SUM(total_alo) AS alo,
        SUM(total_cpc) AS cpc
    FROM dw_collection_recovery_quintoandar.fact_collection
    WHERE DATE(dt_occurrence) >= DATE('2023-01-01')
        AND DATE(dt_occurrence) <= CURRENT_DATE()
    GROUP BY 1,2
),
collections_efforts AS (
    SELECT
        sk_contract,
        esforco,
        alo,
        cpc,
        IF(esforco > 0, TRUE, FALSE) AS has_esforco,
        IF(alo > 0, TRUE, FALSE) AS has_alo,
        IF(cpc > 0, TRUE, FALSE) AS has_cpc,
        dt_reference
    FROM fact_collection_base
),
app_events_features AS (
    SELECT
        DATE(ts_event) AS dt_reference,
        id_contract,
        COUNT(DISTINCT id_amplitude) AS qnt_app_events,
        COUNT(DISTINCT CASE
            WHEN funnel_step IN ('Overdue Self Service Viewed', 'Overdue Self Service Action')
                AND id_invoice IS NOT NULL
            THEN id_amplitude
        END) AS qnt_app_events_overdue,
        COUNT(DISTINCT id_amplitude) > 0 AS has_app_events,
        COUNT(DISTINCT CASE
            WHEN funnel_step IN ('Overdue Self Service Viewed', 'Overdue Self Service Action')
                AND id_invoice IS NOT NULL
            THEN id_amplitude
        END) > 0 AS has_app_events_overdue
    FROM datalake_collections_quintoandar.delinquency_app_events
    WHERE id_contract IS NOT NULL
        AND DATE(ts_event) >= DATE('2023-01-01')
    GROUP BY 1, 2
),
contract_blocklist_timeline AS (
    SELECT DISTINCT
        id_debtor_external AS id_contract,
        is_blocked,
        CASE
            WHEN dt_reference <> DATE(ts_updated)
                AND NOT(is_blocked) THEN TRUE
            ELSE is_blocked
        END AS is_blocked_timeline,
        dt_reference
    FROM
        datalake_trato_feito_clean.blocklist
    LATERAL VIEW EXPLODE(
        SEQUENCE(
            DATE(ts_created),
            IF(is_blocked, CURRENT_DATE(), DATE(ts_updated))
        )) AS dt_reference
    WHERE
        (id_debtor_external > 1
            AND id_debtor_external IS NOT NULL)
),
base_evictions AS (
    SELECT
        id_process,
        process,
        CAST(contract AS BIGINT) AS id_contract,
        DATE(dt_registered) AS dt_registered,
        DATE(dt_arbitral_distribution) AS dt_arbitral_distribution,
        DATE(dt_elaw_closure) AS dt_elaw_closure,
        LEAST(DATE(dt_registered), DATE(dt_arbitral_distribution)) AS dt_begin
    FROM
        datalake_gsheets_clean.evictions_base
    WHERE
        DATE(dt_registered) IS NOT NULL
        AND DATE(dt_registered) >= DATE('2023-01-01')
        AND (
            DATE(dt_elaw_closure) > LEAST(DATE(dt_registered), DATE(dt_arbitral_distribution))
            OR DATE(dt_elaw_closure) IS NULL
        )
),
date_expansion AS (
    SELECT
        d.date AS dt_reference,
        m.*
    FROM
        base_evictions AS m
    CROSS JOIN
        dw_public.dim_date AS d
        ON d.date >= m.dt_begin
        AND d.date <= COALESCE(DATE(m.dt_elaw_closure), CURRENT_DATE())
        AND d.date >= DATE('2023-01-01')
        AND d.date <= CURRENT_DATE()
),
timeline_addition AS (
    SELECT
        *,
        IF(dt_registered > dt_reference, NULL, dt_registered) AS dt_registered_timeline,
        IF(dt_arbitral_distribution > dt_reference, NULL, dt_arbitral_distribution) AS dt_arbitral_distribution_timeline,
        IF(dt_elaw_closure > dt_reference, NULL, dt_elaw_closure) AS dt_elaw_closure_timeline
    FROM
        date_expansion
),
status_timeline_evic AS (
    SELECT
        *,
        CASE
            WHEN dt_elaw_closure_timeline IS NOT NULL THEN 'EVENDED'
            WHEN dt_registered_timeline IS NULL
                AND dt_arbitral_distribution_timeline IS NOT NULL
                AND dt_elaw_closure_timeline IS NULL THEN 'EVEX'
            WHEN dt_registered_timeline IS NOT NULL
                AND dt_arbitral_distribution_timeline IS NOT NULL
                AND dt_elaw_closure_timeline IS NULL THEN 'EVEX'
            WHEN dt_registered_timeline IS NOT NULL
                AND dt_arbitral_distribution_timeline IS NULL
                AND dt_elaw_closure_timeline IS NULL THEN 'EVPD'
            ELSE 'EV-UNDEFINED'
        END AS status_time
    FROM
        timeline_addition
),
evictions_timeline AS (
    SELECT
        id_contract,
        id_process,
        true AS is_evictions,
        dt_reference
    FROM
        status_timeline_evic
    WHERE status_time = 'EVEX'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY id_contract, dt_reference ORDER BY id_process) = 1
),
base_negotiations AS (
    SELECT
        DATE(dt_promisse) AS dt_reference,
        sk_contract,
        COUNT(DISTINCT sk_negotiation) AS promessas,
        COUNT(DISTINCT CASE WHEN dt_down_payment IS NOT NULL THEN sk_negotiation ELSE NULL END) AS acordos,
        COUNT(DISTINCT CASE
            WHEN number_of_installments > 1
                AND promisse_payment_method = 'BOLETO'
                THEN sk_negotiation
            ELSE NULL
        END) AS promessas_neg_parcelada_boleto,
        COUNT(DISTINCT CASE
            WHEN number_of_installments > 1
                AND promisse_payment_method = 'BOLETO'
                AND dt_down_payment IS NOT NULL
            THEN sk_negotiation
            ELSE NULL
        END) AS acordos_neg_parcelada_boleto,
        COUNT(DISTINCT CASE
            WHEN discount_to_original_amount > 1
            THEN sk_negotiation
            ELSE NULL
        END) AS promessas_desconto_principal,
        COUNT(DISTINCT CASE
            WHEN discount_to_original_amount > 1
                AND dt_down_payment IS NOT NULL
            THEN sk_negotiation
            ELSE NULL
        END) AS acordo_desconto_principal,
        COUNT(DISTINCT CASE
            WHEN discount_to_fees_amount > 1
            THEN sk_negotiation
            ELSE NULL
        END) AS promessas_desconto_multas,
        COUNT(DISTINCT CASE
            WHEN discount_to_fees_amount > 1
                AND dt_down_payment IS NOT NULL
            THEN sk_negotiation
            ELSE NULL
        END) AS acordo_desconto_multas,
        COUNT(DISTINCT sk_negotiation) FILTER (WHERE DATE_DIFF(DAY, dt_promisse, dt_cancellation) >= 5 AND dt_down_payment IS NULL) AS qt_promessa_quebrada_fp,
        COUNT(DISTINCT sk_negotiation) FILTER (WHERE dt_down_payment IS NOT NULL
            AND (number_of_installments = 1
                OR promisse_payment_method = 'CARTÃO DE CRÉDITO')) AS qt_acordo_a_vista,
        COUNT(DISTINCT sk_negotiation) FILTER (WHERE dt_down_payment IS NOT NULL
            AND number_of_installments > 1
            AND promisse_payment_method <> 'CARTÃO DE CRÉDITO') AS qt_acordo_parcelado,
        COUNT(DISTINCT sk_negotiation) FILTER (WHERE dt_down_payment IS NOT NULL
            AND number_of_installments > 1
            AND promisse_payment_method <> 'CARTÃO DE CRÉDITO'
            AND negotiation_status = 'broken') AS qt_acordo_quebrado,
        COUNT(DISTINCT sk_negotiation) FILTER (WHERE discount_to_original_amount > 50
        AND dt_down_payment IS NOT NULL) AS qt_aco_desconto

    FROM
        dw_collection_recovery_quintoandar.fact_negotiation
    WHERE
        negotiation_status IN ('broken-requested-by-client',
            'started',
            'offset',
            'broken',
            'finished',
            'canceled')
        AND DATE(dt_promisse) >= DATE('2023-01-01')
        AND DATE(dt_promisse) <= CURRENT_DATE()
    GROUP BY 1,2
),
negotiations AS (
    SELECT *,
        IF(promessas > 0, TRUE, FALSE) AS has_promessas,
        IF(acordos > 0, TRUE, FALSE) AS has_acordos,
        IF(promessas_neg_parcelada_boleto > 0, TRUE, FALSE) AS has_promessas_neg_parcelada_boleto,
        IF(acordos_neg_parcelada_boleto > 0, TRUE, FALSE) AS has_acordos_neg_parcelada_boleto,
        IF(promessas_desconto_principal > 0, TRUE, FALSE) AS has_promessas_desconto_principal,
        IF(acordo_desconto_principal > 0, TRUE, FALSE) AS has_acordo_desconto_principal,
        IF(promessas_desconto_multas > 0, TRUE, FALSE) AS has_promessas_desconto_multas,
        IF(acordo_desconto_multas > 0, TRUE, FALSE) AS has_acordo_desconto_multas
    FROM
        base_negotiations
),
contract_enhanced AS (
    SELECT
        m.*,
        COALESCE(e.is_evictions, FALSE) AS is_evictions,
        COALESCE(e.id_process, NULL) AS id_process_evictions,
        COALESCE(be.esforco, 0) AS esforco,
        COALESCE(be.alo, 0) AS alo,
        COALESCE(be.cpc, 0) AS cpc,
        COALESCE(be.has_esforco, FALSE) AS has_esforco,
        COALESCE(be.has_alo, FALSE) AS has_alo,
        COALESCE(be.has_cpc, FALSE) AS has_cpc,
        COALESCE(app.has_app_events, FALSE) AS has_app_events,
        COALESCE(app.has_app_events_overdue, FALSE) AS has_app_events_overdue,
        COALESCE(app.qnt_app_events, 0) AS qt_app_events,
        COALESCE(app.qnt_app_events_overdue, 0) AS qt_app_events_overdue,
        COALESCE(bl.is_blocked_timeline, FALSE) AS is_blocklisted,
        COALESCE(d.promessas, 0) AS promessas,
        COALESCE(d.qt_acordo_quebrado, 0) AS qt_acordo_quebrado,
        COALESCE(d.qt_promessa_quebrada_fp, 0) AS qt_promessa_quebrada_fp,
        COALESCE(d.qt_acordo_parcelado, 0) AS qt_acordo_parcelado,
        COALESCE(d.qt_aco_desconto, 0) AS qt_aco_deconto
    FROM
        contract_timeline AS m
    LEFT JOIN
        evictions_timeline AS e
            ON e.dt_reference = m.dt_reference
            AND CAST(e.id_contract AS BIGINT) = m.id_contract
    LEFT JOIN
        collections_efforts AS be
            ON be.dt_reference = m.dt_reference
            AND be.sk_contract = m.id_contract
    LEFT JOIN
        app_events_features AS app
            ON app.id_contract = m.id_contract
            AND app.dt_reference = m.dt_reference
    LEFT JOIN
        contract_blocklist_timeline AS bl
            ON bl.id_contract = m.id_contract
            AND bl.dt_reference = m.dt_reference
    LEFT JOIN
        negotiations AS d
            ON d.sk_contract = m.id_contract
            AND d.dt_reference = m.dt_reference
)
SELECT DISTINCT
    id_contract,
    dt_reference,
    id_process_evictions,
    contract_status_beginning_of_month,
    reference_contract_status,
    is_pipeturn_day,
    is_first_day,
    is_last_day,
    is_quitacao_t1,
    is_quitacao_t2,
    is_quitacao_t3,
    is_regular_t1,
    is_current_at_month_start_t1,
    num_has_negotiation_in_contract,
    n_anchor_invoices_not_negativable,
    n_invoices_negativable,
    n_condominio_invoices,
    n_condominio_open_invoices,
    open_condominio_balance,
    n_multa_recisoria_invoices,
    n_multa_recisoria_open_invoices,
    open_multa_recisoria_balance,
    n_acordo_invoices,
    n_acordo_open_invoices,
    open_acordo_balance,
    n_rental_core_invoices,
    n_rental_core_open_invoices,
    open_rental_core_balance,
    n_reparos_invoices,
    n_reparos_open_invoices,
    open_reparos_balance,
    n_multas_ongoing_invoices,
    n_multas_ongoing_open_invoices,
    open_multas_ongoing_balance,
    n_utilidades_invoices,
    n_utilidades_open_invoices,
    open_utilidades_balance,
    n_outros_invoices,
    n_outros_open_invoices,
    open_outros_balance,
    n_overdue_monthlys_t1,
    n_overdue_deals_t1,
    n_overdue_others_t1,
    n_overdue_monthlys_t2,
    n_overdue_deals_t2,
    n_overdue_others_t2,
    sum_overdue_monthlys_t2,
    sum_overdue_deals_t2,
    sum_overdue_others_t2,
    max_delay_original_invoices_t1,
    max_delay_deal_invoices_t1,
    max_delay_original_invoices_t2,
    max_delay_deal_invoices_t2,
    max_delay_contaminated_contract_t2,
    max_delay_contaminated_contract_t3_losses,
    max_delay_contaminated_contract_t1,
    max_open_delay_contaminated_contract_t2,
    max_open_delay_contaminated_contract_t3_losses,
    max_open_delay_contaminated_contract_t1,
    open_wallet,
    wallet,
    recovered_amount,
    wallet_on_time_t1,
    wallet_overdue_t1,
    open_wallet_on_time_t1,
    open_wallet_overdue_t1,
    overdue_recovered_amount_t1,
    on_time_paid_amount_t1,
    wallet_on_time_t2,
    wallet_overdue_t2,
    open_wallet_on_time_t2,
    open_wallet_overdue_t2,
    overdue_recovered_amount_t2,
    on_time_paid_amount_t2,
    wallet_on_time_t3,
    wallet_overdue_t3,
    open_wallet_on_time_t3,
    open_wallet_overdue_t3,
    overdue_recovered_amount_t3,
    on_time_paid_amount_t3,
    sum_monthly_overdue_days_paid_t1,
    count_monthly_overdue_invoices_paid_t1,
    array_open_invoices,
    array_paid_invoices,
    array_negotiated_invoices,
    is_evictions,
    has_app_events,
    has_app_events_overdue,
    is_blocklisted,
    has_esforco,
    has_alo,
    has_cpc,
    esforco,
    alo,
    cpc,
    promessas,
    qt_app_events,
    qt_app_events_overdue,
    qt_acordo_quebrado,
    qt_promessa_quebrada_fp,
    qt_acordo_parcelado,
    qt_aco_deconto,
    CASE
        WHEN reference_contract_status = 'Finalizado'
            THEN 12*(YEAR(dt_contract_end) - YEAR(dt_contract_start)) + (MONTH(dt_contract_end) - MONTH(dt_contract_start))
        ELSE NULL
    END AS mob_finalizacao,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t1 > 0
            AND max_open_delay_contaminated_contract_t1 > 5
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over5_t1_at_ending,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t2 > 0
            AND max_open_delay_contaminated_contract_t2 > 5
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over5_t2_at_ending,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t3 > 0
            AND max_open_delay_contaminated_contract_t2 > 5
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over5_t3_at_ending,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t1 > 0
            AND max_open_delay_contaminated_contract_t1 > 0
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over0_t1_at_ending,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t2 > 0
            AND max_open_delay_contaminated_contract_t2 > 0
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over0_t2_at_ending,
    CASE
        WHEN DATE_TRUNC('MONTH', dt_contract_end) = DATE_TRUNC('MONTH', dt_reference)
            AND open_wallet_overdue_t3 > 0
            AND max_open_delay_contaminated_contract_t2 > 0
        THEN TRUE
        ELSE FALSE
    END AS has_overdue_balance_over0_t3_at_ending,
    DATEDIFF(DAY, dt_contract_end, DATE(dt_reference)) AS days_since_ending,
    DATEDIFF(DAY, dt_contract_start, DATE(dt_reference)) AS days_since_contract_start,
    dt_pipe,
    dt_contract_end,
    dt_contract_start,
    dt_month_start,
    dt_month_end,
    NOW() AS ts_load
FROM contract_enhanced
