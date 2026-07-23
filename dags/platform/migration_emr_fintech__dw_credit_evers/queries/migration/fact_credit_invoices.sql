WITH
get_invoices_agreements_extra AS (
    SELECT
        fni.id_invoice_extra AS id_invoice,
        d.id_invoice AS id_invoice_original,
        d.id_contract,
        fn.sk_negotiation,
        fn.id_negotiation,
        fn.negotiation_status,
        fni.installment_status,
        CASE
            WHEN fn.dt_cancellation IS NOT NULL
                AND fn.dt_paid_all_installments IS NULL
                AND LOWER(fn.negotiation_status) IN ('finished', 'broken', 'offset')
            THEN TRUE
            ELSE FALSE
        END AS is_agreement_broken,
        DATE(fn.dt_cancellation) AS dt_negotiation_cancelation,
        fn.dt_promisse AS dt_negotiation_creation
    FROM
        dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni
    INNER JOIN
        dw_collection_recovery_quintoandar.fact_negotiation fn
            ON fni.sk_negotiation = fn.sk_negotiation
    INNER JOIN
        dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
            ON b.sk_negotiation = fn.sk_negotiation
    INNER JOIN
        dw_collection_recovery_quintoandar.fact_debt AS d
            ON d.sk_debt = b.sk_debt
    INNER JOIN
        datalake_retsuko.invoice AS r
            ON d.id_invoice = r.id_external
    WHERE
        fn.creditor = 'IQ QuintoAndar'
        AND fn.dt_down_payment IS NOT NULL
        AND fn.number_of_installments > 1
        AND fn.promisse_payment_method <> 'CARTÃO DE CRÉDITO'
    GROUP BY ALL
),
get_invoices_agreements_original AS (
    SELECT
        d.id_invoice,
        d.id_contract,
        fn.sk_negotiation,
        fn.id_negotiation,
        fn.negotiation_status,
        CASE
            WHEN fn.dt_cancellation IS NOT NULL
                AND fn.dt_paid_all_installments IS NULL
                AND LOWER(fn.negotiation_status) IN ('finished', 'broken', 'offset')
            THEN TRUE
            ELSE FALSE
        END AS is_agreement_broken,
        DATE(fn.dt_cancellation) AS dt_negotiation_cancelation,
        fn.dt_promisse AS dt_negotiation_creation
    FROM
        dw_collection_recovery_quintoandar.fact_debt AS d
    INNER JOIN
        dw_collection_recovery_quintoandar.bridge_map_debt_negotiation AS b
            ON d.sk_debt = b.sk_debt
    INNER JOIN
        dw_collection_recovery_quintoandar.fact_negotiation fn
            ON b.sk_negotiation = fn.sk_negotiation
    WHERE
        fn.creditor = 'IQ QuintoAndar'
        AND fn.dt_down_payment IS NOT NULL
        AND fn.number_of_installments > 1
        AND fn.promisse_payment_method <> 'CARTÃO DE CRÉDITO'
),
get_all_invoices AS (
    SELECT
        i.id_external AS sk_invoice,
        i.id_contract_external AS sk_contract,
        i.id_contract AS sk_contract_retsuko,
        c.sk_contract AS sk_contract_ebdb,
        flrf.sk_proposal,
        i.purpose,
        i.status,
        i.due_amount,
        i.paid_amount,
        i.accrual_year_month,
        DATE_ADD(
            ADD_MONTHS(
            DATE_FORMAT(
                CAST(
                UNIX_TIMESTAMP(
                    CONCAT(CAST(i.accrual_year_month AS STRING), '01'),
                    'yyyyMMdd'
                ) AS TIMESTAMP
                ),
                'yyyy-MM-dd'
            ),
            1
            ),
            6
        ) AS dt_due_based_accrual_year_month,
        IF(df.id_invoice IS NOT NULL, TRUE, FALSE) AS is_debt_forgiveness,
        IF(f.id_invoice IS NOT NULL, TRUE, FALSE) AS is_fraud,
        acc.type AS account_type,
        c.guarantee AS contract_guarantee,
        c.country_code AS contract_country_code,
        DATE(c.ts_updated) AS dt_contract_updated,
        i.ts_paid,
        i.ts_due,
        i.ts_created,
        i.dt_due_adjusted,
        c.dt_annulment AS dt_contract_termination,
        DATE(c.ts_signature) AS dt_contract_signature
    FROM
        datalake_retsuko.invoice AS i
    LEFT JOIN
        datalake_retsuko.debt_forgiveness AS df
            ON i.id_external = df.id_invoice
            AND i.status IN ("not-payable", "canceled")
    LEFT JOIN
        datalake_invoice.fraud AS f
            ON i.id_external = f.id_invoice
    LEFT JOIN
        datalake_retsuko_clean.account AS acc
            ON acc.id_contract = i.id_contract
    LEFT JOIN
        dw_rent.dim_contract AS c
            ON i.id_contract_external = c.sk_contract
    LEFT JOIN
        dw_rent.fact_listing_rent_flows AS flrf
            ON i.id_contract_external = flrf.sk_contract
    WHERE
        acc.type = 'tenant'
        AND (i.due_amount <0
            OR df.id_invoice IS NOT NULL
        )
),
check_fintech_holidays AS (
    SELECT
        inv.sk_invoice,
        inv.sk_contract,
        inv.sk_contract_retsuko,
        inv.sk_contract_ebdb,
        inv.sk_proposal,
        inv.purpose,
        inv.status,
        inv.due_amount,
        inv.paid_amount,
        inv.accrual_year_month,
        inv.account_type,
        inv.contract_guarantee,
        inv.contract_country_code,
        inv.is_debt_forgiveness,
        inv.is_fraud,
        inv.dt_contract_signature,
        inv.dt_contract_termination,
        inv.dt_contract_updated,
        inv.dt_due_adjusted,
        inv.dt_due_based_accrual_year_month,
        IF(
            dd.is_brz_fintech_business_day,
            inv.dt_due_based_accrual_year_month,
            dd.next_brz_fintech_business_day
        ) AS dt_due_adjusted_based_accrual_year_month,
        inv.ts_paid,
        inv.ts_due,
        inv.ts_created
    FROM
        get_all_invoices AS inv
    LEFT JOIN
        dw_public.dim_date AS dd
            ON dd.sk_date = DATE_FORMAT(inv.dt_due_based_accrual_year_month, "yyyyMMdd")
),
calculate_anchor_agreement AS (
    SELECT
        a.id_invoice,
        a.id_contract,
        a.sk_negotiation,
        a.id_negotiation,
        a.negotiation_status,
        a.installment_status,
        a.is_agreement_broken,
        a.dt_negotiation_cancelation,
        a.dt_negotiation_creation,
        MIN(c.dt_due_adjusted_based_accrual_year_month) AS dt_due_invoice_anchor_agreement
    FROM
        get_invoices_agreements_extra AS a
    LEFT JOIN
        check_fintech_holidays AS c
        ON a.id_invoice_original = c.sk_invoice
    GROUP BY ALL
),
get_agreement_rule AS (
    SELECT
        inv.sk_invoice,
        inv.sk_contract,
        inv.sk_contract_retsuko,
        inv.sk_contract_ebdb,
        inv.sk_proposal,
        COALESCE(agg_extra.sk_negotiation, agg_original.sk_negotiation) AS sk_negotiation,
        COALESCE(agg_extra.id_negotiation, agg_original.id_negotiation) AS id_negotiation_business,
        inv.purpose,
        inv.status,
        COALESCE(agg_extra.negotiation_status, agg_original.negotiation_status) AS negotiation_status,
        inv.due_amount,
        inv.paid_amount,
        inv.accrual_year_month,
        inv.account_type,
        inv.contract_guarantee,
        inv.contract_country_code,
        IFNULL(COALESCE(agg_extra.is_agreement_broken, agg_original.is_agreement_broken), FALSE) AS has_agreement_broken,
        IF(COALESCE(agg_extra.sk_negotiation, agg_original.sk_negotiation) IS NOT NULL, TRUE, FALSE) AS has_agreement,
        inv.is_debt_forgiveness,
        inv.is_fraud,
        inv.dt_contract_signature,
        inv.dt_contract_termination,
        inv.dt_contract_updated,
        inv.dt_due_adjusted,
        COALESCE(agg_extra.dt_negotiation_creation, agg_original.dt_negotiation_creation) AS dt_agreement_creation,
        COALESCE(agg_extra.dt_negotiation_cancelation, agg_original.dt_negotiation_cancelation) AS dt_agreement_cancelation,
        inv.dt_due_based_accrual_year_month,
        inv.dt_due_adjusted_based_accrual_year_month,
        IF(agg_extra.is_agreement_broken, agg_extra.dt_due_invoice_anchor_agreement, inv.dt_due_adjusted_based_accrual_year_month) AS dt_due_calculated,
        inv.ts_paid,
        IF(agg_extra.is_agreement_broken IS TRUE, NULL, inv.ts_paid) AS ts_paid_calculated,
        inv.ts_due,
        inv.ts_created
    FROM
        check_fintech_holidays AS inv
    LEFT JOIN
        calculate_anchor_agreement AS agg_extra
            ON inv.sk_invoice = agg_extra.id_invoice
    LEFT JOIN
        get_invoices_agreements_original AS agg_original
            ON inv.sk_invoice = agg_original.id_invoice
)
SELECT
    sk_invoice,
    sk_contract,
    sk_contract_retsuko,
    sk_contract_ebdb,
    sk_proposal,
    sk_negotiation,
    id_negotiation_business,
    purpose,
    status,
    negotiation_status,
    due_amount,
    paid_amount,
    accrual_year_month,
    account_type,
    contract_guarantee,
    contract_country_code,
    has_agreement_broken,
    has_agreement,
    is_debt_forgiveness,
    is_fraud,
    dt_contract_signature,
    dt_contract_termination,
    dt_contract_updated,
    dt_due_adjusted,
    dt_agreement_cancelation,
    dt_due_based_accrual_year_month,
    dt_due_adjusted_based_accrual_year_month,
    dt_due_calculated,
    ts_paid,
    ts_paid_calculated,
    ts_due,
    ts_created,
    NOW() AS ts_load
FROM
  get_agreement_rule
WHERE
    IFNULL(DATEDIFF(dt_due_calculated, dt_contract_signature), -1) > 0
    AND status != 'canceled'
    AND contract_guarantee NOT IN ('Standalone','ThirdPartyGuarantee')
    AND contract_country_code = 'BR'
