-- FLOW TYPE CTE
WITH flow_type AS (
    WITH last_sf_entry AS (
        SELECT
            row_number() OVER (
                PARTITION BY
                id
                ORDER BY
                ts_updated DESC
            ) AS ROW,
            id,
            flow_type
        FROM
            datalake_sales_flow_clean.sales_flow
    )
    SELECT
        o.id_firestore AS id_offer,
        sf.flow_type
    FROM
        datalake_sales_flow_clean.offer AS o
    LEFT JOIN
        last_sf_entry AS sf
            ON sf.id = o.id_sales_flow
            AND sf.row = 1
    GROUP BY
        1,
        2
),
-- OFFERS CTE
offers AS (
    WITH last_offer_entry AS (
        SELECT
            row_number() OVER (
                PARTITION BY
                id_firestore
                ORDER BY
                ts_updated DESC
            ) AS ROW,
            *
        FROM
            datalake_sales_flow_clean.offer
    )
    SELECT
        id_firestore AS id_offer,
        id_sales_flow,
        sale_price,
        status,
        discard_reason,
        ts_accepted,
        ts_discarded
    FROM
        last_offer_entry
    WHERE
        ROW = 1
),
-- SALES FLOW CTE
last_update_sales_flow AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.sales_flow
    GROUP BY
        1
),
sales_flow AS (
    SELECT
        sf.id,
        sf.id_house,
        sf.flow_type,
        sf.status,
        sf.flow_step,
        sf.status_closing
    FROM
        datalake_sales_flow_clean.sales_flow AS sf
    INNER JOIN
        offers sfo
            ON sfo.id_sales_flow = sf.id
    INNER JOIN
        last_update_sales_flow AS lusf
            ON sf.id = lusf.id
            AND sf.ts_updated = lusf.ts_last_updated
),
-- CCVS CTE
ccvs AS (
    WITH last_ccv_entry AS (
        SELECT
            row_number() OVER (
                PARTITION BY id_sales_flow
                ORDER BY
                ts_updated DESC
            ) AS ROW,
            *
        FROM
            datalake_sales_flow_clean.ccv_flow
    ),

    offers_ccvs AS (
        SELECT
            id_firestore AS id_offer,
            id_sales_flow
        FROM
            datalake_sales_flow_clean.offer AS o
        GROUP BY
            1,
            2
    ),

    specialists_ccvs AS (
        WITH last_specialist AS (
            SELECT
                row_number() OVER (
                PARTITION BY id_sales_flow,
                kind
                ORDER BY
                    ts_updated DESC
                ) AS ROW,
                *
            FROM
                datalake_sales_flow_clean.specialist
        ),
        offers_specialists AS (
            SELECT
                id_firestore AS id_offer,
                id_sales_flow
            FROM
                datalake_sales_flow_clean.offer AS o
            GROUP BY
                1,
                2
        )
        SELECT
            id_offer,
            dm.id_specialist AS id_consultant
        FROM
            offers_specialists AS o
        LEFT JOIN
            last_specialist AS dm
                ON dm.id_sales_flow = o.id_sales_flow
                AND dm.kind = 'DEAL_MAKER'
                AND dm.row = 1
        LEFT JOIN
            last_specialist AS tl
                ON tl.id_sales_flow = o.id_sales_flow
                AND tl.kind = 'TEAM_LEAD'
                AND tl.row = 1
    )

    SELECT
        o.id_offer,
        lce.ts_signed,
        lce.ts_created
    FROM
        offers_ccvs AS o
    LEFT JOIN
        specialists_ccvs AS s
            ON s.id_offer = o.id_offer
    INNER JOIN
        last_ccv_entry AS lce
            ON lce.id_sales_flow = o.id_sales_flow
            AND lce.row =1
            AND (
                    (unix_timestamp(lce.ts_signed) - unix_timestamp(lce.ts_created)) > 0
                    OR (s.id_consultant IS NOT NULL AND lce.status = 'SIGNED' )
                )
),
-- CCV FLOW CTE
last_update_ccv_flow AS (
    SELECT
        id_ccv_flow,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.ccv_flow
    GROUP BY
        1
),
ccv_flow AS (
    SELECT
        ccv_flow.id_ccv_flow,
        ccv_flow.id_sales_flow,
        ccv_flow.status,
        DATE(ts_confection_started) AS dt_confection_started,
        DATE(ts_signed) AS dt_sale_agreement_signed
    FROM
        datalake_sales_flow_clean.ccv_flow AS ccv_flow
    INNER JOIN
        last_update_ccv_flow AS lucf
        ON ccv_flow.id_ccv_flow = lucf.id_ccv_flow
        AND ccv_flow.ts_updated = lucf.ts_last_updated
),
-- PENDENCY CTE
last_update_pendency AS (
    SELECT
        id_sales_flow,
        MAX(ts_updated) as ts_last_updated
    FROM datalake_sales_flow_clean.sales_flow_pendency
    GROUP BY 1
),
pendency AS (
    SELECT
        sfp.id,
        sfp.id_sales_flow,
        pendency,
        type,
        ts_last_updated
    FROM
        datalake_sales_flow_clean.sales_flow_pendency as sfp
    INNER JOIN
        last_update_pendency as lup
        ON lup.ts_last_updated = sfp.ts_updated
        AND sfp.id_sales_flow = lup.id_sales_flow
),
-- MORTGAGE CTE
last_update_mortgage AS (
    SELECT
        id_mortgage,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.mortgage
    GROUP BY
        1
),
mortgage AS (
    SELECT
        mg.id_mortgage,
        mg.id_sales_flow,
        mg.bank,
        mg.status,
        mg.credit_model,
        mg.credit_status,
        mg.dt_bank_started,
        mg.dt_credit_started,
        mg.dt_credit_ended,
        mg.dt_started,
        mg.dt_ended,
        DATE(mg.ts_seller_paid) AS dt_seller_paid
    FROM
        datalake_sales_flow_clean.mortgage AS mg
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = mg.id_sales_flow
    INNER JOIN
        last_update_mortgage AS lum
        ON mg.id_mortgage = lum.id_mortgage
        AND mg.ts_updated = lum.ts_last_updated
),
-- PAYMENT CTE
last_update_payment AS (
    SELECT
        id_sales_flow,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.payment
    GROUP BY
        id_sales_flow
    ),
payment AS (
    SELECT
        p.id as id_payment,
        p.id_sales_flow,
        p.status,
        p.payment_model
    FROM
        datalake_sales_flow_clean.payment AS p
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = p.id_sales_flow
    INNER JOIN
        last_update_payment AS lup
        ON p.id_sales_flow = lup.id_sales_flow
        AND p.ts_updated = lup.ts_last_updated
),
-- CASH PAYMENT CTE
last_update_cash_payment AS (
    SELECT
        id_cash_payment,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.cash_payment
    GROUP BY
        id_cash_payment
    ),
cash_payment AS (
    SELECT
        cp.id_cash_payment,
        cp.id_payment,
        cp.crn_details,
        DATE(cp.ts_crn_started) AS dt_crn_started,
        DATE(cp.ts_crn_ended) AS dt_crn_ended
    FROM
        datalake_sales_flow_clean.cash_payment AS cp
    INNER JOIN
        last_update_cash_payment AS lucp
        ON cp.id_cash_payment = lucp.id_cash_payment
        AND cp.ts_updated = lucp.ts_last_updated
),
-- NOTARY CTE
last_update_notary AS (
    SELECT
        id_notary,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.notary
    GROUP BY
        id_notary
),
notary AS (
    SELECT
        n.id_notary,
        n.id_sales_flow,
        n.status,
        DATE(n.ts_started) AS dt_started,
        DATE(n.ts_ended) AS dt_ended,
        DATE(n.ts_seller_paid) AS dt_seller_paid,
        DATE(n.ts_buyer_received_keys) AS dt_buyer_received_keys
    FROM
        datalake_sales_flow_clean.notary AS n
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = n.id_sales_flow
    INNER JOIN
        last_update_notary AS lun
        ON n.id_notary = lun.id_notary
        AND n.ts_updated = lun.ts_last_updated
),
-- DILIGENCE CTE
last_update_diligence AS (
    SELECT
        id_diligence,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.diligence
    GROUP BY
        id_diligence
),
diligence AS (
    SELECT
        d.id_diligence,
        d.id_sales_flow,
        d.classification,
        d.step,
        d.ts_buyer_seller_ended,
        d.ts_partner_started,
        d.ts_partner_ended,
        d.ts_legal_risk_started,
        d.ts_legal_risk_ended
    FROM
        datalake_sales_flow_clean.diligence AS d
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = d.id_sales_flow
    INNER JOIN
        last_update_diligence AS lud
        ON d.id_diligence = lud.id_diligence
        AND d.ts_updated = lud.ts_last_updated
),
-- DILIGENCE APPOINTMENT
last_update_diligence_appointment AS (
    SELECT
        id_diligence_appointment,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.diligence_appointment
    GROUP BY
        id_diligence_appointment
),
diligence_appointment AS (
  SELECT
      da.id_diligence,
      concat_ws(' - ',collect_set(appointment)) AS appointment
  FROM
      datalake_sales_flow_clean.diligence_appointment as da
  INNER JOIN
      last_update_diligence_appointment AS luda
        ON da.id_diligence_appointment = luda.id_diligence_appointment
        AND da.ts_updated = luda.ts_last_updated
  GROUP BY id_diligence
),
-- HOUSE CTE
last_update_house AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.house
    GROUP BY
        id
),
house AS (
    SELECT
        h.id,
        h.has_seller_debt_payments
    FROM
        datalake_sales_flow_clean.house AS h
    INNER JOIN
        last_update_house AS luh
        ON h.id = luh.id
        AND h.ts_updated = luh.ts_last_updated
),
-- RESCISION CTE
last_update_rescission AS (
    SELECT
        id_rescission,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.rescission
    GROUP BY
        id_rescission
),
rescission AS (
    SELECT
        r.id_rescission,
        r.id_sales_flow,
        r.comment
    FROM
        datalake_sales_flow_clean.rescission AS r
    INNER JOIN
        last_update_rescission AS lur
        ON r.id_rescission = lur.id_rescission
        AND r.ts_updated = lur.ts_last_updated
),
-- ONBOARDING CTE
status_closing_changes AS (
    SELECT
        id,
        ts_updated,
        LAG(status_closing)
        OVER (
            PARTITION BY
                id
            ORDER BY
                ts_updated
        ) AS previous_status
    FROM
        datalake_sales_flow_clean.sales_flow_aud
    WHERE
        mod_status_closing
),
onboarding AS (
    SELECT
        id AS id_sales_flow,
        DATE(MAX(ts_updated)) AS dt_ended
    FROM
        status_closing_changes
    WHERE
        previous_status = 'ONBOARDING'
    GROUP BY
        id_sales_flow
),
-- TAG CTE
last_update_tag AS (
    SELECT
        id,
        MAX(ts_updated) AS ts_last_updated
    FROM
        datalake_sales_flow_clean.tag
    GROUP BY
        id
),
tag AS (
    SELECT
        id_sales_flow,
        concat_ws('; ',collect_set(concat('#',label))) AS label
    FROM
        datalake_sales_flow_clean.sales_flow_tag AS sftag
    INNER JOIN
        datalake_sales_flow_clean.tag AS tag
            ON sftag.id_tag = tag.id
    INNER JOIN
        last_update_tag AS lut
            ON tag.id = lut.id
            AND tag.ts_updated = lut.ts_last_updated
    GROUP BY
        id_sales_flow
)
SELECT
    off.id_offer,
    sp.id_user_consultant,
    sp.id_consultant,
    off.id_sales_flow,
    sp.id_user_team_lead AS sk_user_team_lead,
    sp.id_team_lead AS sk_team_lead,
    sp.id_user_pre_specialist,
    sp.id_pre_specialist,
    sp.id_user_post_specialist,
    sp.id_post_specialist,
    sp.id_user_credit_specialist,
    sp.id_credit_specialist,
    sp.id_user_start_financing_specialist,
    sp.id_start_financing_specialist,
    sp.id_user_follow_up_financing_specialist,
    sp.id_follow_up_financing_specialist,
    sp.id_user_end_financing_specialist,
    sp.id_end_financing_specialist,
    sp.id_user_notes_registry_specialist,
    sp.id_notes_registry_specialist,
    sp.id_user_real_estate_register_specialist,
    sp.id_real_estate_register_specialist,
    sp.id_user_legal_risk_analyst,
    sp.id_legal_risk_analyst,
    sfp.id as id_pendency,
    sfp.pendency,
    sfp.type as pendency_type,
    mg.bank AS financing_bank,
    CASE
        WHEN sf.flow_step = 'CANCELED_ON_NEGOTIATION'
        THEN 'Canceladas em negociação'
        WHEN sf.flow_step = 'PROPOSAL_ON_VALIDATION'
        THEN 'Propostas em validação'
        WHEN sf.flow_step = 'PURCHASE_SALE_COMPLETED'
        THEN 'Compra e Venda Concluídas'
        WHEN sf.flow_step = 'POST_CCV'
        THEN 'Pós CCV'
        WHEN sf.flow_step = 'CANCELED_ON_VALIDATION'
        THEN 'Canceladas em validação'
        WHEN sf.flow_step = 'CANCELED_POST_ACCEPTED'
        THEN 'Canceladas pós Aceite'
        WHEN sf.flow_step = 'CANCELED_CCV'
        THEN 'CCV - Cancelado'
        WHEN sf.flow_step = 'PROPOSAL_ONGOING'
        THEN 'Propostas Ongoing'
        WHEN sf.flow_step = 'PROPOSAL_ACCEPTED'
        THEN 'Propostas Aceitas'
        WHEN sf.flow_step = 'POST_CCV_HUB_CT'
        THEN 'Pós CCV Hub CT'
        ELSE sf.flow_step
    END AS flow_step,
    off.status as vendas_offer_status,
    ccvf.status AS sale_agreement_status,
    sf.flow_type AS negotiation_model,
    ft.flow_type,
    CASE
        WHEN ft.flow_type LIKE '%HUB%'
        THEN 'HUB'
        WHEN ft.flow_type LIKE '%CENTRAL%'
        THEN 'CENTRAL'
        WHEN ft.flow_type = 'DEFAULT'
        THEN 'DEAL_MAKING'
    END AS vendas_offer_flow,
    r.comment AS sale_agreement_cancellation_reason,
    off.discard_reason AS drop_reason,
    CASE
        WHEN LOWER(off.discard_reason) LIKE '%buyer%'
        THEN 'Buyer'
        WHEN LOWER(off.discard_reason) LIKE '%seller%'
        THEN 'Seller'
        ELSE 'Other'
    END AS drop_reason_responsible,
    mg.credit_model AS credit_model,
    p.payment_model,
    sp.consultant_name,
    sp.consultant_email,
    sp.team_lead_name,
    sp.team_lead_email,
    sp.pre_specialist_name,
    sp.pre_specialist_email,
    sp.post_specialist_name,
    sp.post_specialist_email,
    sp.credit_specialist_name,
    sp.credit_specialist_email,
    sp.start_financing_specialist_name,
    sp.start_financing_specialist_email,
    sp.follow_up_financing_specialist_name,
    sp.follow_up_financing_specialist_email,
    sp.end_financing_specialist_name,
    sp.end_financing_specialist_email,
    sp.notes_registry_specialist_name,
    sp.notes_registry_specialist_email,
    sp.real_estate_register_specialist_name,
    sp.real_estate_register_specialist_email,
    sp.legal_risk_analyst_name,
    sp.legal_risk_analyst_email,
    sf.status_closing AS closing_status,
    d.classification AS house_dilligence_status,
    da.appointment AS diligence_appointment_reason,
    sf.status AS seller_dilligence_status,
    d.step AS report_dilligence_status,
    mg.status AS bank_analysis_status,
    p.status AS payment_status,
    mg.credit_status AS credit_status,
    n.status AS notary_office_status,
    cp.crn_details AS real_estate_register_office_status,
    tag.label AS tags_from_salesflow,
    off.sale_price AS sale_price_agreed,
    CASE
        WHEN DATE(off.ts_accepted) <= DATE(off.ts_discarded)
        THEN DATEDIFF(DATE(off.ts_discarded), DATE(off.ts_accepted))
    END AS days_offer_accepted_to_offer_dismissed,
    DATEDIFF(
        ccvf.dt_confection_started,
        DATE(off.ts_accepted)
    ) AS days_offer_accepted_to_sale_agreement_created,
    DATEDIFF(
        ccvf.dt_sale_agreement_signed,
        DATE(off.ts_accepted)
    ) AS days_offer_accepted_to_sale_agreement_signed,
    DATEDIFF(
        ccvf.dt_sale_agreement_signed,
        ccvf.dt_confection_started
    ) AS days_sale_agreement_created_to_sale_agreement_signed,
    h.has_seller_debt_payments,
    CASE
        WHEN ccvf.dt_sale_agreement_signed IS NOT NULL
        THEN
            CASE
            WHEN sf.flow_step = 'CANCELED_CCV' THEN TRUE
            ELSE FALSE
            END
        ELSE NULL
    END AS is_ccv_canceled,
    ccvf.dt_confection_started AS dt_sale_agreement_created,
    ccvf.dt_sale_agreement_signed AS dt_sale_agreement_signed,
    CASE
        WHEN sf.flow_step = 'CANCELED_CCV'
        THEN DATE(off.ts_discarded)
    END AS dt_sale_agreement_cancelled,
    o.dt_ended AS dt_onboarding_ended,
    DATE(d.ts_buyer_seller_ended) AS dt_legal_analysis_ended,
    DATE(d.ts_partner_started) AS dt_legaut_analysis_started,
    DATE(d.ts_partner_ended) AS dt_legaut_analysis_ended,
    DATE(d.ts_legal_risk_started) AS dt_legal_risk_started,
    DATE(d.ts_legal_risk_ended) AS dt_legal_risk_ended,
    DATE(mg.dt_bank_started) AS dt_bank_legal_analysis_started,
    DATE(mg.dt_credit_started) AS dt_credit_analysis_started,
    DATE(mg.dt_credit_ended) AS dt_credit_analysis_ended,
    DATE(mg.dt_started) AS dt_financing_started,
    DATE(mg.dt_ended) AS dt_financing_ended,
    cp.dt_crn_started AS dt_notes_registry_started,
    cp.dt_crn_ended AS dt_notes_registry_ended,
    n.dt_started AS dt_house_registry_started,
    n.dt_ended AS dt_house_registry_ended,
    COALESCE(mg.dt_seller_paid, n.dt_seller_paid) AS dt_sale_transacton_paid,
    n.dt_buyer_received_keys AS dt_sale_key_delivered,
    off.ts_accepted,
    off.ts_discarded,
    ccv.ts_signed,
    ccv.ts_created,
    sfp.ts_last_updated as ts_last_updated_pendency
FROM
    offers AS off
LEFT JOIN
    sales_flow AS sf
        ON sf.id = off.id_sales_flow
LEFT JOIN
    flow_type AS ft
        ON ft.id_offer = off.id_offer
LEFT JOIN
    ccvs AS ccv
        ON ccv.id_offer = off.id_offer
LEFT JOIN
    datalake_sale_offer_flows.offer_specialists AS sp
        ON sp.id_offer = off.id_offer
LEFT JOIN
    mortgage AS mg
        ON mg.id_sales_flow = off.id_sales_flow
LEFT JOIN
    ccv_flow AS ccvf
        ON ccvf.id_sales_flow = off.id_sales_flow
LEFT JOIN
    payment AS p
        ON p.id_sales_flow = off.id_sales_flow
LEFT JOIN
    cash_payment AS cp
        ON cp.id_payment = p.id_payment
LEFT JOIN
    notary AS n
        ON n.id_sales_flow = off.id_sales_flow
LEFT JOIN
    diligence AS d
        ON d.id_sales_flow = off.id_sales_flow
LEFT JOIN
    diligence_appointment AS da
        ON da.id_diligence = d.id_diligence
LEFT JOIN
    house AS h
        ON h.id = sf.id_house
LEFT JOIN
    rescission AS r
        ON r.id_sales_flow = off.id_sales_flow
LEFT JOIN
    onboarding AS o
        ON o.id_sales_flow = off.id_sales_flow
LEFT JOIN
    tag
        ON tag.id_sales_flow = off.id_sales_flow
LEFT JOIN
    pendency AS sfp
        ON sfp.id_sales_flow = off.id_sales_flow
WHERE
    tag.label IS NULL
    OR tag.label NOT LIKE '%#offertestedeproduto%'
