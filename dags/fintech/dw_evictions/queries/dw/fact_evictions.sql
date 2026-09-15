WITH
region AS (
    SELECT DISTINCT
        d.sk_contract,
        g.short_region_name AS region,
        g.city_name AS city
    FROM dw_rent.fact_listing_rent_flows d
    LEFT JOIN dw_rent.dim_house_listing f
        ON f.sk_house_listing = d.sk_house_listing
    LEFT JOIN dw_public.dim_region g
        ON g.sk_region = d.sk_region
),
aux_calendar AS (
    SELECT
        d.sk_date,
        d.month_start,
        d.month_end,
        d.date,
        d.quarter,
        d.weekend,
        d.is_brz_holiday,
        CASE WHEN d.date BETWEEN DATE('2025-12-22') AND DATE('2026-01-02') THEN True ELSE False END AS arbitration_recess,
        CASE WHEN d.date BETWEEN DATE('2025-12-20') AND DATE('2026-01-19') THEN True ELSE False END AS judicial_recess
    FROM dw_public.dim_date AS d
        WHERE d.month_start <= DATE(DATE_TRUNC('month',CURRENT_DATE()))
),
-- Original join was `dt_registered <= d.date` with timestamp vs date (midnight).
-- A registration with time after 00:00 excludes that calendar day; DATE() SEQUENCE
-- would include it and add one business-day to LDTs.
eviction_spine_bounds AS (
    SELECT
        eb.id_process,
        eb.contract,
        eb.dt_registered,
        eb.dt_closure,
        CASE
            WHEN eb.dt_registered IS NULL THEN NULL
            WHEN eb.dt_registered <= CAST(DATE(eb.dt_registered) AS TIMESTAMP)
            THEN DATE(eb.dt_registered)
            ELSE DATE_ADD(DATE(eb.dt_registered), 1)
        END AS dt_spine_from,
        COALESCE(
            DATE(eb.dt_closure),
            (SELECT MAX(ac.date) FROM aux_calendar AS ac)
        ) AS dt_spine_to
    FROM
        datalake_cyber_legal.evictions_base AS eb
),
eviction_date_spine AS (
    SELECT
        esb.id_process,
        esb.contract,
        esb.dt_registered,
        esb.dt_closure,
        EXPLODE_OUTER(
            CASE
                WHEN esb.dt_spine_from IS NOT NULL
                    AND esb.dt_spine_from <= esb.dt_spine_to
                THEN SEQUENCE(esb.dt_spine_from, esb.dt_spine_to)
                ELSE ARRAY()
            END
        ) AS date
    FROM
        eviction_spine_bounds AS esb
),
eviction_calendar AS (
    SELECT
        eds.id_process,
        eds.contract,
        eds.dt_registered,
        eds.dt_closure,
        ac.sk_date,
        ac.date,
        ac.is_brz_holiday,
        ac.weekend,
        ac.arbitration_recess
    FROM
        eviction_date_spine AS eds
    LEFT JOIN
        aux_calendar AS ac
            ON eds.date = ac.date
),
fpd AS (
    SELECT id_invoice
    FROM (SELECT
              invoice.id_external AS id_invoice,
              ROW_NUMBER() OVER (PARTITION BY invoice.id_contract_external ORDER BY invoice.dt_due_adjusted, invoice.ts_created) AS row_number
          FROM datalake_retsuko.invoice AS invoice
          LEFT JOIN datalake_retsuko.invoice_info AS invoice_info
              ON invoice.id_external = invoice_info.id_invoice
          LEFT JOIN dw_rent.dim_contract AS contract
              ON invoice.id_contract_external = contract.id_contract
          WHERE invoice_info.invoice_user = 'tenant'
              AND invoice.due_amount < 0
              AND invoice.status != 'canceled'
              AND contract.status != 'Cancelado'
              AND contract.country_code = 'BR'
    ) AS retsuko_data
    WHERE row_number = 1
),
overdue_filtrado AS (
    SELECT *
    FROM dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline
    WHERE dt_invoice_paid IS NULL
),
overdue AS (
    SELECT
        o.sk_contract,
        o.dt_reference,
        o.delay_contamined_range,
        DATEDIFF(o.dt_reference, MIN(o.dt_invoice_due_adjust)) AS delay_days,
        SUM(o.due_amount) AS open_amount,
        COUNT(o.id_invoice) AS invoices,
        COUNT(CASE WHEN o.invoice_type = 'monthly' THEN o.id_invoice END) AS monthly_invoices,
        COUNT(CASE WHEN o.negotiation_installment_number IS NOT NULL THEN o.id_invoice END) AS negotiation_invoices,
        COUNT(CASE WHEN fpd.id_invoice IS NOT NULL THEN o.id_invoice END) AS fpd_invoices
    FROM overdue_filtrado o
    LEFT JOIN fpd ON o.id_invoice = fpd.id_invoice
    GROUP BY 1, 2, 3
),
negotiation AS (
    SELECT
        fn.sk_contract,
        DATE(fn.dt_down_payment) AS dt_down_payment,
        fni.id_invoice_extra,
        fni.dt_paid
    FROM dw_collection_recovery_quintoandar.fact_negotiation_installment AS fni
    LEFT JOIN dw_collection_recovery_quintoandar.fact_negotiation AS fn
        ON fni.sk_negotiation = fn.sk_negotiation
    WHERE fn.dt_down_payment IS NOT NULL
    AND fni.installment_number >= 2
),
negotiation_at_registration AS (
    SELECT DISTINCT
        eb.id_process,
        TRUE AS has_active_negotiation_at_registration
    FROM datalake_cyber_legal.evictions_base AS eb
    INNER JOIN negotiation AS n
        ON n.sk_contract = BIGINT(TRIM(eb.contract))
        AND n.dt_down_payment <= DATE(eb.dt_registered)
        AND (
            n.dt_paid > DATE(eb.dt_registered)
            OR n.dt_paid IS NULL
        )
),
process_evictions AS (
    SELECT
        eb.id_process AS sk_process,
        CAST(eb.contract AS BIGINT) AS sk_contract,
        DATE(COALESCE(eb.dt_closure, dt.max_dt_reference)) AS dt_reference,
        DATE(DATEADD(day, -10, COALESCE(eb.dt_closure, dt.max_dt_reference))) AS dt_limite
    FROM datalake_cyber_legal.evictions_base eb
    CROSS JOIN (
        SELECT MAX(dt_reference) AS max_dt_reference
        FROM dw_collection_recovery_quintoandar.fact_overdue_portfolio_timeline
    ) dt
),
overdue_order AS (
    SELECT
        pv.sk_process,
        o.sk_contract,
        o.dt_reference,
        o.due_amount,
        o.id_invoice,
        o.invoice_type,
        o.negotiation_installment_number,
        o.delay_contamined_range,
        o.dt_invoice_due_adjust,
        DENSE_RANK() OVER (PARTITION BY pv.sk_process ORDER BY CASE WHEN o.dt_reference = pv.dt_reference THEN 1 ELSE 2 END, o.dt_reference DESC) AS rn
  FROM overdue_filtrado o
  LEFT JOIN process_evictions pv
        ON pv.sk_contract = o.sk_contract
        AND o.dt_reference BETWEEN pv.dt_limite AND pv.dt_reference
),
overdue_final as (
    SELECT
        oo.sk_process,
        oo.sk_contract,
        oo.dt_reference,
        oo.delay_contamined_range,
        SUM(oo.due_amount) AS open_amount
    FROM overdue_order AS oo
    WHERE rn = 1
    GROUP BY 1,2,3,4
),
collection_agency_at_reference AS (
    SELECT
        eb.id_process,
        at.id_agency AS id_agency_group,
        at.juridical_agency,
        at.conventional_agency,
        COALESCE(DATE(eb.dt_closure), CURRENT_DATE) AS dt_collection_reference
    FROM datalake_cyber_legal.evictions_base AS eb
    LEFT JOIN datalake_cyber.agency_timeline AS at
        ON CAST(eb.contract AS BIGINT) = at.id_contract
        AND COALESCE(DATE(eb.dt_closure), CURRENT_DATE) = at.dt_reference
)

SELECT
    e.id_process AS sk_process,
    e.contract AS sk_contract,
    'cyber_legal' AS source,
    e.process AS process,
    e.input_type AS input_type,
    CASE
        WHEN o1.open_amount IS NULL THEN 'Adimplente'
        WHEN o1.fpd_invoices > 0 THEN 'FPD'
        WHEN nar.has_active_negotiation_at_registration
            OR o1.negotiation_invoices > 0 THEN 'Acordo Ativo'
        WHEN o1.monthly_invoices > 0 THEN 'Mensal'
        WHEN o1.open_amount IS NOT NULL THEN 'Demais Inadimplentes'
        ELSE 'Outros'
    END AS contract_category_at_registration,
    e.action_type AS action_type,
    e.action AS action,
    CASE
        WHEN e.office IN ('PLC', 'LLC') THEN 'LLC'
        ELSE e.office
    END AS office,
    CASE
        WHEN e.dt_registered < DATE('2025-10-17') AND e.dt_closure < DATE('2025-12-15') AND e.office = 'VZL' THEN 'PASCHOALOTTO'
        WHEN UPPER(COALESCE(ca.id_agency_group, '')) IN ('G224', '224') THEN 'BULGARELLI'
        WHEN UPPER(COALESCE(ca.id_agency_group, '')) IN ('G024', '024') AND ca.dt_collection_reference >= DATE('2026-07-01') THEN 'VZL'
        WHEN UPPER(COALESCE(ca.id_agency_group, '')) IN ('G024', '024') THEN 'BULGARELLI'
        WHEN e.office = 'VZL' THEN 'BULGARELLI'
        WHEN e.office = 'GDM' THEN 'GONDIM'
        WHEN e.office = 'PLL' THEN 'PELLON'
        WHEN e.office = 'PLC' THEN 'LLC'
        WHEN e.office = 'LLC' THEN 'LLC'
        WHEN e.office = 'PSC' THEN 'PASCHOALOTTO'
        ELSE e.office
    END AS collection_agency,
    e.chamber,
    r.region,
    r.city,
    CASE
        WHEN c.dt_ended_rental_confirmed IS NOT NULL THEN 'Finalizado'
        WHEN c.ts_expected_termination IS NOT NULL AND c.dt_ended_rental_confirmed IS NULL THEN 'Finalizando'
        ELSE 'Ativo'
    END AS contract_status,
    e.cyber_status,
    e.last_stage,
    e.arbitral_distribution_expense_amount,
    e.arbitral_citation_expense_amount,
    e.arbitral_sentence_expense_amount,
    e.judiciary_distribution_expense_amount,
    e.judicial_summons_decision_expense_amount,
    e.judicial_summons_expense_amount,
    e.coercive_decision_expense_amount,
    e.coercive_issuance_expense_amount,
    e.judicial_petition_expense_amount,
    e.possession_imission_decision_expense_amount,
    e.possession_imission_issuance_expense_amount,
    e.execution_requirement_expense_amount,
    e.prejudgment_attachment_expense_amount,
    e.execution_citation_expense_amount,
    e.asset_attachment_expense_amount,
    e.asset_evaluation_expense_amount,
    e.credit_satisfaction_expense_amount,
    'not_in_cyber_legal' AS passage_status,
    e.procedure,
    e.first_consolidated_reason AS consolidated_reason,
    e.first_standardized_reason AS standardized_reason,
    e.result,
    o1.delay_days AS overdue_days_at_registration,
    e.succumbency_fee,
    COALESCE(c.rent, 0) + COALESCE(c.iptu, 0) + COALESCE(c.condo, 0) AS total_package,
    ovf.open_amount AS total_due_amount,
    e.ldt_stock AS ldt_stock,
    e.stock_range AS stock_range,
    e.ldt_resolution AS ldt_resolution,
    CASE
        WHEN e.ldt_resolution BETWEEN 0 AND 120 THEN '<120D'
        WHEN e.ldt_resolution BETWEEN 121 AND 240 THEN '120-240D'
        WHEN e.ldt_resolution BETWEEN 241 AND 360 THEN '240-360D'
        WHEN e.ldt_resolution BETWEEN 361 AND 5000 THEN '>360D'
        ELSE NULL
    END AS resolution_range,
    e.ldt_coercive AS ldt_coercive,
    e.last_occurrence AS last_occurrence,
    DATE_DIFF(DAY, DATE(e.dt_registered), e.dt_closure) AS real_ldt_resolution,
        --leadtimes despejo
    COUNT(DISTINCT
        CASE
            WHEN DATE(e.dt_registered) <= d.date AND DATE(e.dt_registered) IS NOT NULL
            AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
            AND(
              (DATE(e.dt_arbitral_distribution_start) IS NOT NULL AND DATE(e.dt_arbitral_distribution_start) >= d.date) OR
              (DATE(e.dt_arbitral_distribution_start) IS NULL AND CURRENT_DATE() >= d.date)
              ) THEN d.sk_date END) AS ldt_arbitral_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_distribution_start) <= d.date AND DATE(e.dt_arbitral_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_arbitral_citation_start) IS NOT NULL AND DATE(e.dt_arbitral_citation_start) >= d.date) OR
                  (DATE(e.dt_arbitral_citation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_arbitral_citation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_distribution_start) <= d.date AND DATE(e.dt_arbitral_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_arbitral_sentence_start) IS NOT NULL AND DATE(e.dt_arbitral_sentence_start) >= d.date) OR
                  (DATE(e.dt_arbitral_sentence_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_arbitral_award,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_arbitral_sentence_start) <= d.date AND DATE(e.dt_arbitral_sentence_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judiciary_distribution_start) IS NOT NULL AND DATE(e.dt_judiciary_distribution_start) >= d.date) OR
                  (DATE(e.dt_judiciary_distribution_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judiciary_distribution,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judiciary_distribution_start) <= d.date AND DATE(e.dt_judiciary_distribution_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_summons_decision_start) IS NOT NULL AND DATE(e.dt_judicial_summons_decision_start) >= d.date) OR
                  (DATE(e.dt_judicial_summons_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_decision_start) <= d.date AND DATE(e.dt_judicial_summons_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_summons_start) IS NOT NULL AND DATE(e.dt_judicial_summons_start) >= d.date) OR
                  (DATE(e.dt_judicial_summons_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_decision_start) <= d.date AND DATE(e.dt_judicial_summons_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_coercive_decision_start) IS NOT NULL AND DATE(e.dt_coercive_decision_start) >= d.date) OR
                  (DATE(e.dt_coercive_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_decision,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_coercive_decision_start) <= d.date AND DATE(e.dt_coercive_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_coercive_issuance_start) IS NOT NULL AND DATE(e.dt_coercive_issuance_start) >= d.date) OR
                  (DATE(e.dt_coercive_issuance_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_coercive_order_issuance_decision,
    --leadtimes reivindicatoria
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_registered) <= d.date AND DATE(e.dt_registered) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_petition_start) IS NOT NULL AND DATE(e.dt_judicial_petition_start) >= d.date) OR
                  (DATE(e.dt_judicial_petition_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_petition_r,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_petition_start) <= d.date AND DATE(e.dt_judicial_petition_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_judicial_summons_decision_start) IS NOT NULL AND DATE(e.dt_judicial_summons_decision_start) >= d.date) OR
                  (DATE(e.dt_judicial_summons_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_judicial_summons_decision_r,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_judicial_summons_start) <= d.date AND DATE(e.dt_judicial_summons_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_possession_imission_decision_start) IS NOT NULL AND DATE(e.dt_possession_imission_decision_start) >= d.date) OR
                  (DATE(e.dt_possession_imission_decision_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_possesion_imission_decisions_r,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_possession_imission_decision_start) <= d.date AND DATE(e.dt_possession_imission_decision_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_possession_imission_issuance_start) IS NOT NULL AND DATE(e.dt_possession_imission_issuance_start) >= d.date) OR
                  (DATE(e.dt_possession_imission_issuance_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_possesion_imission_issuance_r,
    --leadtimes execucao
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_registered) <= d.date AND DATE(e.dt_registered) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_execution_requirement_start) IS NOT NULL AND DATE(e.dt_execution_requirement_start) >= d.date) OR
                  (DATE(e.dt_execution_requirement_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_execution_requirement,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_execution_requirement_start) <= d.date AND DATE(e.dt_execution_requirement_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_prejudgment_attachment_start) IS NOT NULL AND DATE(e.dt_prejudgment_attachment_start) >= d.date) OR
                  (DATE(e.dt_prejudgment_attachment_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_prejudgment_attachment,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_prejudgment_attachment_start) <= d.date AND DATE(e.dt_prejudgment_attachment_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_execution_citation_start) IS NOT NULL AND DATE(e.dt_execution_citation_start) >= d.date) OR
                  (DATE(e.dt_execution_citation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_execution_citation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_execution_citation_start) <= d.date AND DATE(e.dt_execution_citation_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_asset_attachment_start) IS NOT NULL AND DATE(e.dt_asset_attachment_start) >= d.date) OR
                  (DATE(e.dt_asset_attachment_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_asset_attachment,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_asset_attachment_start) <= d.date AND DATE(e.dt_asset_attachment_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_asset_evaluation_start) IS NOT NULL AND DATE(e.dt_asset_evaluation_start) >= d.date) OR
                  (DATE(e.dt_asset_evaluation_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_asset_evaluation,
    COUNT(DISTINCT
            CASE
                WHEN DATE(e.dt_asset_evaluation_start) <= d.date AND DATE(e.dt_asset_evaluation_start) IS NOT NULL
                AND d.is_brz_holiday = "No holiday" AND d.weekend = 'Weekday' AND d.arbitration_recess = False
                AND(
                  (DATE(e.dt_credit_satisfaction_start) IS NOT NULL AND DATE(e.dt_credit_satisfaction_start) >= d.date) OR
                  (DATE(e.dt_credit_satisfaction_start) IS NULL AND CURRENT_DATE() >= d.date)
                  ) THEN d.sk_date END) AS ldt_credit_satisfaction,
    e.has_arbitration_defense,
    e.has_redistribution,
    e.is_reincident,
    e.is_reopened,
    e.dt_registered,
    e.dt_arbitral_distribution_start,
    e.dt_arbitral_distribution_end,
    e.dt_arbitral_citation_start,
    e.dt_arbitral_citation_end,
    e.dt_arbitral_contestation,
    e.dt_arbitral_sentence_start,
    e.dt_arbitral_sentence_end,
    e.dt_judiciary_pre_registration,
    e.dt_judiciary_distribution_start,
    e.dt_judiciary_distribution_end,
    e.dt_judicial_summons_decision_start,
    e.dt_judicial_summons_decision_end,
    e.dt_judicial_summons_start,
    e.dt_judicial_summons_end,
    e.dt_judicial_defense,
    e.dt_coercive_decision_start,
    e.dt_coercive_decision_end,
    e.dt_coercive_issuance_start,
    e.dt_coercive_issuance_end,
    e.dt_judicial_petition_start,
    e.dt_judicial_petition_end,
    e.dt_possession_imission_decision_start,
    e.dt_possession_imission_decision_end,
    e.dt_possession_imission_issuance_start,
    e.dt_possession_imission_issuance_end,
    e.dt_execution_requirement_start,
    e.dt_execution_requirement_end,
    e.dt_prejudgment_attachment_start,
    e.dt_prejudgment_attachment_end,
    e.dt_execution_citation_start,
    e.dt_execution_citation_end,
    e.dt_asset_attachment_start,
    e.dt_asset_attachment_end,
    e.dt_asset_evaluation_start,
    e.dt_asset_evaluation_end,
    e.dt_credit_satisfaction_start,
    e.dt_credit_satisfaction_end,
    e.dt_closure,
    c.dt_ended_rental_confirmed AS dt_finalizing,
    c.ts_expected_termination AS dt_finalized_erc,
    e.ts_updated,
    NOW() AS ts_load
FROM
    datalake_cyber_legal.evictions_base e
LEFT JOIN
    eviction_calendar AS d
        ON COALESCE(e.id_process, '') = COALESCE(d.id_process, '')
        AND COALESCE(e.contract, '') = COALESCE(d.contract, '')
        AND e.dt_registered <=> d.dt_registered
        AND e.dt_closure <=> d.dt_closure
LEFT JOIN
    overdue_final AS ovf
    ON ovf.sk_process = e.id_process
LEFT JOIN
    overdue AS o1
        ON e.contract = o1.sk_contract
        AND DATE_ADD(DATE(e.dt_registered), -1) = o1.dt_reference
LEFT JOIN
    dw_rent.dim_contract c
    ON e.contract = c.id_contract
LEFT JOIN
    region r
    ON e.contract = r.sk_contract
LEFT JOIN
    collection_agency_at_reference AS ca
    ON e.id_process = ca.id_process
LEFT JOIN
    negotiation_at_registration AS nar
    ON e.id_process = nar.id_process
GROUP BY
    e.id_process,
    e.contract,
    e.process,
    e.input_type,
    e.action_type,
    e.action,
    e.office,
    e.chamber,
    r.region,
    r.city,
    e.cyber_status,
    e.last_stage,
    e.arbitral_distribution_expense_amount,
    e.arbitral_citation_expense_amount,
    e.arbitral_sentence_expense_amount,
    e.judiciary_distribution_expense_amount,
    e.judicial_summons_decision_expense_amount,
    e.judicial_summons_expense_amount,
    e.coercive_decision_expense_amount,
    e.coercive_issuance_expense_amount,
    e.judicial_petition_expense_amount,
    e.possession_imission_decision_expense_amount,
    e.possession_imission_issuance_expense_amount,
    e.execution_requirement_expense_amount,
    e.prejudgment_attachment_expense_amount,
    e.execution_citation_expense_amount,
    e.asset_attachment_expense_amount,
    e.asset_evaluation_expense_amount,
    e.credit_satisfaction_expense_amount,
    e.procedure,
    e.first_consolidated_reason,
    e.first_standardized_reason,
    e.result,
    o1.delay_days,
    o1.open_amount,
    o1.fpd_invoices,
    o1.negotiation_invoices,
    o1.monthly_invoices,
    e.succumbency_fee,
    c.rent,
    c.iptu,
    c.condo,
    ovf.open_amount,
    e.ldt_stock,
    e.stock_range,
    e.ldt_resolution,
    e.ldt_coercive,
    e.last_occurrence,
    e.dt_registered,
    e.dt_closure,
    c.dt_ended_rental_confirmed,
    c.ts_expected_termination,
    ca.id_agency_group,
    ca.dt_collection_reference,
    nar.has_active_negotiation_at_registration,
    e.has_arbitration_defense,
    e.has_redistribution,
    e.is_reincident,
    e.is_reopened,
    e.dt_arbitral_distribution_start,
    e.dt_arbitral_distribution_end,
    e.dt_arbitral_citation_start,
    e.dt_arbitral_citation_end,
    e.dt_arbitral_contestation,
    e.dt_arbitral_sentence_start,
    e.dt_arbitral_sentence_end,
    e.dt_judiciary_pre_registration,
    e.dt_judiciary_distribution_start,
    e.dt_judiciary_distribution_end,
    e.dt_judicial_summons_decision_start,
    e.dt_judicial_summons_decision_end,
    e.dt_judicial_summons_start,
    e.dt_judicial_summons_end,
    e.dt_judicial_defense,
    e.dt_coercive_decision_start,
    e.dt_coercive_decision_end,
    e.dt_coercive_issuance_start,
    e.dt_coercive_issuance_end,
    e.dt_judicial_petition_start,
    e.dt_judicial_petition_end,
    e.dt_possession_imission_decision_start,
    e.dt_possession_imission_decision_end,
    e.dt_possession_imission_issuance_start,
    e.dt_possession_imission_issuance_end,
    e.dt_execution_requirement_start,
    e.dt_execution_requirement_end,
    e.dt_prejudgment_attachment_start,
    e.dt_prejudgment_attachment_end,
    e.dt_execution_citation_start,
    e.dt_execution_citation_end,
    e.dt_asset_attachment_start,
    e.dt_asset_attachment_end,
    e.dt_asset_evaluation_start,
    e.dt_asset_evaluation_end,
    e.dt_credit_satisfaction_start,
    e.dt_credit_satisfaction_end,
    e.ts_updated
