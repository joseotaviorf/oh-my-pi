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
-- VENDAS SPECIALIST CTE
specialists AS (
    WITH last_specialist AS (
        SELECT
            row_number() OVER (
                PARTITION BY 
                id_sales_flow,
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
        dm.id_main_user AS id_user_consultant,
        dm.specialist_name AS consultant_name,
        dm.id_specialist AS id_consultant,
        dm.email AS consultant_email,
        tl.specialist_name AS team_lead_name,
        tl.email AS team_lead_email,
        tl.id_main_user AS sk_user_team_lead,
        tl.id_specialist AS sk_team_lead
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
        mg.credit_status
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
        p.payment_method
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
        DATE(n.ts_seller_paid) AS dt_seller_paid
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
        d.step
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
)
SELECT
    off.id_offer,
    sp.id_user_consultant,
    sp.id_consultant,
    off.id_sales_flow,
    sp.sk_user_team_lead,
    sp.sk_team_lead,
    mg.bank AS financing_bank,
    sf.flow_step,
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
    sp.consultant_name,
    sp.consultant_email,
    sp.team_lead_name,
    sp.team_lead_email,
    sf.status_closing AS closing_status,
    d.classification AS house_dilligence_status,
    sf.status AS seller_dilligence_status,
    d.step AS report_dilligence_status,
    mg.status AS bank_analysis_status,
    p.status AS payment_status,
    mg.credit_status AS credit_status,
    n.status AS notary_office_status,
    cp.crn_details AS real_estate_register_office_status,
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
    n.dt_started AS dt_house_registry_started,
    n.dt_ended AS dt_house_registry_ended,
    n.dt_seller_paid AS dt_sale_transacton_paid,
    off.ts_accepted,
    off.ts_discarded,
    ccv.ts_signed,
    ccv.ts_created    
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
    specialists AS sp 
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
    house AS h 
        ON h.id = sf.id_house
LEFT JOIN 
    rescission AS r 
        ON r.id_sales_flow = off.id_sales_flow
