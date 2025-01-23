  -- FLOW TYPE CTE
WITH flow_type AS (
    WITH last_sf_entry AS (
        SELECT
            ROW_NUMBER() OVER (
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
        o.id_firestore,
        sf.flow_type
),
-- OFFERS CTE
offers AS (
    WITH first_offer_entry AS (
        SELECT
            *
        FROM
            datalake_sales_flow_clean.offer
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY ts_updated) = 1
    ),
    last_offer_entry AS (
        SELECT
            *
        FROM
            datalake_sales_flow_clean.offer
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id_firestore ORDER BY ts_updated DESC) = 1
    ),
    last_reason_entry AS (
        SELECT
            *
        FROM
            datalake_sales_flow_clean.reject_reason
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
    )
    SELECT
        l.id_firestore AS id_offer,
        l.id_sales_flow,
        l.id_hub,
        l.sale_price,
        f.offer_price AS first_price_offered_by_buyer,
        l.offer_price AS last_price_offered_by_buyer,
        l.final_price,
        l.registry_price,
        l.itbi_price,
        l.status,
        COALESCE(lre.reason, l.discard_reason) AS discard_reason,
        lre.source AS reject_source,
        l.ts_created,
        l.ts_accepted,
        l.ts_updated,
        l.ts_discarded
    FROM
        last_offer_entry AS l
    LEFT JOIN
        first_offer_entry AS f
            ON l.id_firestore = f.id_firestore
    LEFT JOIN
        last_reason_entry AS lre
            ON l.id_reject_reason = lre.id

),
-- SALES FLOW CTE
last_update_sales_flow AS (
    SELECT
        sf.*,
        buyer.id_external AS buyer_id_external,
        seller.id_external AS seller_id_external,
        ROW_NUMBER() OVER (PARTITION BY sf.id ORDER BY sf.ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.sales_flow sf
    LEFT JOIN datalake_sales_flow_clean.users AS seller
      ON sf.id_seller = seller.id
    LEFT JOIN datalake_sales_flow_clean.users AS buyer
      ON sf.id_buyer = buyer.id
),
sales_flow AS (
    SELECT
        sf.id,
        sf.id_house,
        buyer_id_external AS id_buyer,
        seller_id_external AS id_seller,
        sf.flow_type,
        sf.status,
        sf.flow_step,
        sf.status_closing,
        sf.closing_canceled_reason,
        sf.is_canceled,
        sf.ts_canceled
    FROM
        last_update_sales_flow AS sf
    INNER JOIN
        offers AS sfo
            ON sfo.id_sales_flow = sf.id
    WHERE
        ROW = 1
),
-- CCVS CTE
ccvs AS (
    WITH last_ccv_entry AS (
        SELECT
            ROW_NUMBER() OVER (
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
            id_firestore,
            id_sales_flow
    ),

    specialists_ccvs AS (
        WITH last_specialist AS (
            SELECT
                ROW_NUMBER() OVER (
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
                id_firestore,
                id_sales_flow
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
        o.id_sales_flow,
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
                    (UNIX_TIMESTAMP(lce.ts_signed) - UNIX_TIMESTAMP(lce.ts_created)) > 0
                    OR (s.id_consultant IS NOT NULL AND lce.status = 'SIGNED' )
                )
),
-- CCV FLOW CTE
last_update_ccv_flow AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.ccv_flow
),
ccv_flow AS (
    SELECT
        ccv_flow.id_ccv_flow,
        ccv_flow.id_sales_flow,
        ccv_flow.status,
        ccv_flow.is_5a_model,
        DATE(ts_confection_started) AS dt_confection_started,
        DATE(ts_signed) AS dt_sale_agreement_signed
    FROM
        last_update_ccv_flow AS ccv_flow
    WHERE
        ROW = 1
),
-- SALES FLOWS DETAILS CTE
last_update_details AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.sales_flow_details
),
sales_flow_details AS (
    SELECT
        sfd.id,
        sfd.id_sales_flow,
        opportunities_of_the_week,
        isolve_link,
        google_drive_link,
        ts_seller_fup,
        ts_buyer_fup,
        ts_updated
    FROM
        last_update_details AS sfd
    WHERE
        ROW = 1
),
-- PENDENCY CTE
last_update_pendency AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.sales_flow_pendency
),
pendency AS (
    SELECT
        sfp.id,
        sfp.id_sales_flow,
        pendency,
        type,
        ts_updated
    FROM
        last_update_pendency AS sfp
    WHERE
        ROW = 1
),
-- MORTGAGE CTE
last_update_mortgage AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_mortgage ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.mortgage
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
        last_update_mortgage AS mg
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = mg.id_sales_flow
    WHERE
        ROW = 1
),
-- PAYMENT CTE
last_update_payment AS (
    SELECT
        *
    FROM
        datalake_sales_flow_clean.payment
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
),
first_update_payment AS (
    SELECT
        *,
        payment_method AS planned_payment_method
    FROM
        datalake_sales_flow_clean.payment
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated ASC) = 1
),
payment AS (
    SELECT
        p.id as id_payment,
        p.id_sales_flow,
        p.status,
        p.payment_model,
        p.payment_method,
        fpm.planned_payment_method,
        p.fgts_value,
        p.entry_amount,
        p.down_payment_value
    FROM
        last_update_payment AS p
    INNER JOIN
        first_update_payment AS fpm
            ON p.id = fpm.id
    INNER JOIN
        offers AS sfo
            ON sfo.id_sales_flow = p.id_sales_flow
),
-- CASH PAYMENT CTE
last_update_cash_payment AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_cash_payment ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.cash_payment
    ),
cash_payment AS (
    SELECT
        cp.id_cash_payment,
        cp.id_payment,
        cp.status_notary_notes,
        cp.crn_details,
        DATE(cp.ts_crn_started) AS dt_crn_started,
        DATE(cp.ts_crn_ended) AS dt_crn_ended
    FROM
        last_update_cash_payment AS cp
    WHERE
        ROW = 1
),
-- NOTARY CTE
last_update_notary AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_notary ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.notary
),
notary AS (
    SELECT
        n.id_notary,
        n.id_sales_flow,
        n.status,
        DATE(n.ts_started) AS dt_started,
        DATE(n.ts_ended) AS dt_ended,
        DATE(n.ts_buyer_received_keys) AS dt_buyer_received_keys
    FROM
        last_update_notary AS n
    INNER JOIN
        offers AS sfo
            ON sfo.id_sales_flow = n.id_sales_flow
    WHERE
        ROW = 1
),
-- DILIGENCE CTE
last_update_diligence AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_diligence ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.diligence
),
diligence AS (
    SELECT
        d.id_diligence,
        d.id_sales_flow,
        d.classification,
        d.step,
        d.ts_buyer_sent,
        d.ts_seller_sent,
        d.ts_buyer_seller_ended,
        d.ts_partner_started,
        d.ts_partner_ended,
        d.ts_legal_risk_started,
        d.ts_legal_risk_ended
    FROM
        last_update_diligence AS d
    INNER JOIN
        offers AS sfo
        ON sfo.id_sales_flow = d.id_sales_flow
    WHERE
        ROW = 1
),
-- DILIGENCE APPOINTMENT
last_update_diligence_appointment AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_diligence_appointment ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.diligence_appointment
),
diligence_appointment AS (
    SELECT
        da.id_diligence,
        CONCAT_WS(' - ', COLLECT_SET(appointment)) AS appointment
    FROM
        last_update_diligence_appointment AS da
    WHERE
        ROW = 1
  GROUP BY id_diligence
),
-- HOUSE CTE
last_update_house AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.house
),
house AS (
    SELECT
        h.id,
        h.id_external,
        h.has_seller_debt_payments,
        h.house_registration_status
    FROM
        last_update_house AS h
    WHERE
        ROW =1
),
-- MONOPOLY CTE
last_update_offer_monopoly AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_event DESC) AS ROW
    FROM
        datalake_monopoly_clean.sale_revision
),
monopoly AS (
    SELECT
         id_external_offer AS id_offer,
         financed_amount AS financing_value
    FROM
        last_update_offer_monopoly
    WHERE ROW = 1
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
        DATE(MIN(ts_updated)) AS dt_ended
    FROM
        status_closing_changes
    WHERE
        previous_status = 'ONBOARDING'
        AND ts_updated < '2022-04-12'
    GROUP BY
        id_sales_flow
),
-- ONBOARDING FROM STATUS ENRICH CTE
onboarding_status AS (
  SELECT
      id_sales_flow,
      id_firestore AS id_offer,
      DATE(ts_macro_status_end) AS dt_onboarding_ended
  FROM
      datalake_sale_offer_flows.sale_offer_status
  WHERE
      macro_status_name = 'ONBOARDING'
      AND DATE(ts_macro_status_end) > DATE('2022-04-12')
),
credit_analysis_status AS (
    SELECT
        id_sales_flow,
        id_firestore AS id_offer,
        last_micro_status_name AS credit_analysis_status_name
    FROM
        datalake_sale_offer_flows.sale_offer_status
    WHERE
        macro_status_name = "CREDIT_ANALYSIS"
        AND DATE(ts_macro_status_end) > DATE('2022-04-12')
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow, macro_status_name ORDER BY ts_micro_status_last_update DESC) = 1
),
-- TAG CTE
last_update_tag AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS ROW
    FROM
        datalake_sales_flow_clean.tag
),
tag AS (
    SELECT
        id_sales_flow,
        CONCAT_WS('; ', COLLECT_SET(CONCAT('#',label))) AS label
    FROM
        datalake_sales_flow_clean.sales_flow_tag AS sftag
    INNER JOIN
        last_update_tag AS tag
            ON sftag.id_tag = tag.id
    WHERE
        ROW = 1
    GROUP BY
        id_sales_flow
),
-- OFFER/SALE AGREEMENT RESCUE FLOW CTE
rescue_flow AS (
    WITH offers_history AS (
        SELECT
            id_sales_flow,
            id_firestore AS id_offer,
            MAX(ts_accepted) ts_last_offer_accepted,
            MAX(ts_discarded) AS ts_last_offer_discarded,
            IF(MAX(ts_accepted) > MAX(ts_discarded), True, False) AS is_a_rescued_offer
        FROM
            datalake_sales_flow_clean.offer_aud
        GROUP BY 1, 2
   ),
   cancelation_history AS (
        SELECT
            id,
            is_canceled,
            closing_canceled_reason,
            LAG(is_canceled, 1) OVER (PARTITION BY id ORDER BY ts_updated) AS last_cancelation_status,
            LAG(ts_updated, 1) OVER (PARTITION BY id ORDER BY ts_updated) AS ts_last_canceled,
            ts_updated
        FROM
            datalake_sales_flow_clean.sales_flow_aud
        QUALIFY
            last_cancelation_status IS DISTINCT FROM is_canceled
    ),
    rescue_and_cancelation_status AS (
        SELECT
            id AS id_sales_flow,
            closing_canceled_reason,
            is_canceled,
            CASE
                WHEN is_canceled = FALSE AND last_cancelation_status = TRUE THEN TRUE
            END AS is_a_rescue,
            CASE
                WHEN is_canceled = FALSE AND last_cancelation_status = TRUE THEN ts_updated
            END AS ts_rescued,
            ts_last_canceled,
            ts_updated,
            ccvs.ts_signed
        FROM
            cancelation_history AS ch
        LEFT JOIN
            ccvs
                ON ch.id = ccvs.id_sales_flow
   ),
   canceled_ccvs AS (
        SELECT
            id_sales_flow,
            CASE
                WHEN closing_canceled_reason IS NOT NULL THEN ts_updated
                ELSE NULL
            END AS ts_sale_agreement_canceled,
            ts_signed,
            ts_rescued
        FROM
            rescue_and_cancelation_status
        WHERE
            ts_last_canceled IS NOT NULL
            AND closing_canceled_reason IS NOT NULL
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
   ),
   rescued_offers AS (
        SELECT
            ofh.id_sales_flow,
            ofh.id_offer,
            ofh.is_a_rescued_offer,
            ofh.ts_last_offer_discarded,
            rcs.ts_rescued
        FROM
            offers_history AS ofh
        INNER JOIN
            rescue_and_cancelation_status AS rcs
                ON rcs.id_sales_flow = ofh.id_sales_flow
                AND ofh.ts_last_offer_discarded <= rcs.ts_last_canceled
        WHERE
            rcs.is_a_rescue = TRUE
            AND closing_canceled_reason IS NULL
        QUALIFY
            ROW_NUMBER() OVER (PARTITION BY rcs.id_sales_flow ORDER BY rcs.ts_updated DESC) = 1
     )
        SELECT
            sf.id AS id_sales_flow,
            rof.id_offer,
            rof.is_a_rescued_offer,
            IF(c_ccvs.ts_rescued IS NOT NULL, True, False) AS is_a_rescued_ccv,
            rof.ts_last_offer_discarded AS ts_offer_canceled,
            c_ccvs.ts_sale_agreement_canceled,
            rof.ts_rescued AS ts_offer_rescued,
            c_ccvs.ts_rescued AS ts_sale_agreement_rescued
        FROM
            sales_flow AS sf
        LEFT JOIN
            rescued_offers AS rof
                ON rof.id_sales_flow = sf.id
        LEFT JOIN
            canceled_ccvs AS c_ccvs
                ON c_ccvs.id_sales_flow = sf.id
),
-- BROKERAGE CTE
brokerage AS (
    SELECT
        id_sales_flow,
        quinto_andar_brokerage_split,
        brokerage_fee,
        brokerage_fee_payer
    FROM
        datalake_sales_flow_clean.brokerage
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_sales_flow ORDER BY ts_updated DESC) = 1
)
SELECT
    off.id_offer,
    sp.id_user_consultant,
    sp.id_consultant,
    sf.id_buyer,
    sf.id_seller,
    h.id_external AS id_house,
    CONCAT(sf.id_buyer,'_', h.id_external) AS id_sale_flow,
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
    sp.id_user_agent,
    sp.id_agent,
    sp.id_user_post_dd_specialist,
    sp.id_post_dd_specialist,
    sfp.id as id_pendency,
    off.id_hub,
    sfp.pendency,
    sfp.type AS pendency_type,
    mg.bank AS financing_bank,
    sfd.opportunities_of_the_week,
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
    off.status AS vendas_offer_status,
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
      CASE WHEN ft.flow_type = 'DEFAULT'
           THEN TRUE
           ELSE FALSE
      END AS has_used_negotiation_chat,
    sf.closing_canceled_reason AS sale_agreement_cancellation_reason,
    off.discard_reason AS drop_reason,
    CASE
        WHEN off.reject_source = 'BUYER' OR off.reject_source IS NULL AND LOWER(off.discard_reason) LIKE '%buyer%'
        THEN 'Buyer'
        WHEN off.reject_source = 'SELLER' OR off.reject_source IS NULL AND LOWER(off.discard_reason) LIKE '%seller%'
        THEN 'Seller'
        ELSE 'Other'
    END AS drop_reason_responsible,
    mg.credit_model AS credit_model,
    p.payment_model,
    p.payment_method,
    p.planned_payment_method,
    mpl.financing_value,
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
    sp.agent_name,
    sp.agent_email,
    sp.post_dd_specialist_name,
    sp.post_dd_specialist_email,
    sf.status_closing AS closing_status,
    h.house_registration_status AS house_dilligence_status,
    da.appointment AS diligence_appointment_reason,
    d.classification AS seller_dilligence_status,
    d.step AS report_dilligence_status,
    mg.status AS bank_analysis_status,
    p.status AS payment_status,
    p.fgts_value,
    p.down_payment_value,
    CASE WHEN p.payment_method LIKE '%USING_FGTS'
         THEN TRUE
         ELSE FALSE
    END AS has_used_fgts_in_payment,
    p.entry_amount,
    COALESCE(cas.credit_analysis_status_name, mg.credit_status) AS credit_status,
    n.status AS real_estate_register_office_status,
    cp.status_notary_notes AS notary_office_status,
    cp.crn_details AS notary_office_details,
    tag.label AS tags_from_salesflow,
    b.brokerage_fee_payer,
    off.sale_price AS sale_listing_price,
    off.registry_price,
    off.itbi_price,
    off.first_price_offered_by_buyer,
    off.last_price_offered_by_buyer,
    CASE
        WHEN off.sale_price IS NULL OR off.first_price_offered_by_buyer IS NULL
            THEN NULL
        ELSE 1-1.00*off.first_price_offered_by_buyer/off.sale_price
    END AS first_discount_proposed,
    CASE
        WHEN off.sale_price IS NULL OR off.last_price_offered_by_buyer IS NULL
            THEN NULL
        ELSE 1-1.00*off.last_price_offered_by_buyer/off.sale_price
    END AS last_discount_proposed,
    off.final_price AS sale_price_agreed,
    COALESCE(b.brokerage_fee, 0.06::DECIMAL(5,4)) AS brokerage_fee, -- 6% default, hard coded in sales-flow
    b.quinto_andar_brokerage_split,
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
    COALESCE(
        sf.is_canceled,
        CASE
            WHEN ccvf.dt_sale_agreement_signed IS NOT NULL
            THEN
                CASE
                    WHEN sf.flow_step = 'CANCELED_CCV' THEN TRUE
                    ELSE FALSE
                END
            ELSE NULL
    END
    ) AS is_ccv_canceled,
    rf.is_a_rescued_ccv,
    rf.is_a_rescued_offer,
    ccvf.is_5a_model AS is_ccv_5a_model,
    ccvf.dt_confection_started AS dt_sale_agreement_created,
    ccvf.dt_sale_agreement_signed AS dt_sale_agreement_signed,
    NULLIF(DATE(rf.ts_sale_agreement_canceled), '0001-01-1') AS dt_sale_agreement_cancelled,
    NULLIF(DATE(rf.ts_offer_rescued), '0001-01-1') AS dt_offer_rescued,
    NULLIF(DATE(rf.ts_sale_agreement_rescued), '0001-01-1') AS dt_sale_agreement_rescued,
    NULLIF(COALESCE(os.dt_onboarding_ended, o.dt_ended), '0001-01-1') AS dt_onboarding_ended,
    NULLIF(DATE(d.ts_buyer_sent), '0001-01-1') AS dt_diligence_buyer_sent_at,
    NULLIF(DATE(d.ts_seller_sent), '0001-01-1') AS dt_diligence_seller_sent_at,
    NULLIF(DATE(d.ts_buyer_seller_ended), '0001-01-1') AS dt_legal_analysis_ended,
    NULLIF(DATE(d.ts_partner_started), '0001-01-1') AS dt_legaut_analysis_started,
    NULLIF(DATE(d.ts_partner_ended), '0001-01-1') AS dt_legaut_analysis_ended,
    NULLIF(DATE(d.ts_legal_risk_started), '0001-01-1') AS dt_legal_risk_started,
    NULLIF(DATE(d.ts_legal_risk_ended), '0001-01-1') AS dt_legal_risk_ended,
    NULLIF(DATE(mg.dt_bank_started), '0001-01-1') AS dt_bank_legal_analysis_started,
    NULLIF(DATE(mg.dt_credit_started), '0001-01-1') AS dt_credit_analysis_started,
    NULLIF(DATE(mg.dt_credit_ended), '0001-01-1') AS dt_credit_analysis_ended,
    NULLIF(DATE(mg.dt_started), '0001-01-1') AS dt_financing_started,
    NULLIF(DATE(mg.dt_ended), '0001-01-1') AS dt_financing_ended,
    NULLIF(cp.dt_crn_started, '0001-01-1') AS dt_notes_registry_started,
    NULLIF(cp.dt_crn_ended, '0001-01-1') AS dt_notes_registry_ended,
    NULLIF(n.dt_started, '0001-01-1') AS dt_house_registry_started,
    NULLIF(n.dt_ended, '0001-01-1') AS dt_house_registry_ended,
    NULLIF(mg.dt_seller_paid, '0001-01-1') AS dt_sale_transacton_paid,
    NULLIF(n.dt_buyer_received_keys, '0001-01-1') AS dt_sale_key_delivered,
    NULLIF(off.ts_created, '0001-01-1') AS ts_offer_created,
    NULLIF(off.ts_accepted, '0001-01-1') AS ts_accepted,
    NULLIF(off.ts_discarded, '0001-01-1') AS ts_discarded,
    sfd.ts_seller_fup,
    sfd.ts_buyer_fup,
    ccv.ts_signed,
    ccv.ts_created,
    off.ts_updated AS ts_offer_updated,
    sfp.ts_updated AS ts_last_updated_pendency
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
    onboarding AS o
        ON o.id_sales_flow = off.id_sales_flow
LEFT JOIN
    onboarding_status AS os
        ON os.id_sales_flow = off.id_sales_flow
LEFT JOIN
    tag
        ON tag.id_sales_flow = off.id_sales_flow
LEFT JOIN
    pendency AS sfp
        ON sfp.id_sales_flow = off.id_sales_flow
LEFT JOIN
    sales_flow_details AS sfd
        ON sfd.id_sales_flow = off.id_sales_flow
LEFT JOIN
    rescue_flow AS rf
        ON off.id_sales_flow = rf.id_sales_flow
LEFT JOIN
    credit_analysis_status AS cas
        ON cas.id_sales_flow = sf.id
LEFT JOIN
    brokerage AS b
        ON b.id_sales_flow = off.id_sales_flow
LEFT JOIN
    monopoly AS mpl
        ON off.id_offer = mpl.id_offer
WHERE
    tag.label IS NULL
    OR tag.label NOT LIKE '%#offertestedeproduto%'
