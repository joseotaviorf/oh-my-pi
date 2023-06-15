WITH closing_infos AS (-- Get all ccv that were cancelled and were not rescued
    SELECT
        sk_offer
    FROM
        dw_sale.fact_closing_flows
    WHERE
         sk_sale_agreement_cancelled_date != -1
    GROUP BY
        1
    HAVING
        MAX(sk_sale_agreement_cancelled_date) > MAX(sk_sale_agreement_rescued_date)
),
ev AS (
    SELECT DISTINCT
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer,
        ROW_NUMBER() OVER (PARTITION BY sf.sk_buyer ORDER BY sf.sk_sale_agreement_signed_date DESC) AS rn,
        dd.date AS dt_event
    FROM
        dw_sale.fact_sale_flows AS sf
    INNER JOIN
        dw_public.dim_region AS dr
            ON sf.sk_region = dr.sk_region
            AND dr.id_country = 1
    JOIN
        dw_public.dim_date AS dd
            ON sf.sk_sale_agreement_signed_date = dd.sk_date
    INNER JOIN
        dw_sale.fact_offers fo
            ON sf.sk_sale_flow = fo.sk_sale_flow
    LEFT JOIN
        closing_infos ci
            ON fo.sk_offer = ci.sk_offer
    WHERE
        sf.sk_sale_agreement_signed_date >= 20200101
        AND ci.sk_offer IS NULL
),
rent_visits AS (
    SELECT
        id_visitor,
        MAX(dt_scheduling) AS dt_visit_rent
    FROM
        dw_public.dim_booking
    WHERE
        visit_intent = 'RENT' AND
        type = 'Visita' AND
        visit_follow_up = 'VaiNegociar'
    GROUP BY 1
),
base AS (
    SELECT
        ev.sk_buyer,
        ev.dt_event,
        ev.sk_offer,
        du.sk_user,
        du.cpf,
        du.nome,
        du.email,
        du.telefone_principal,
        du.cidade,
        du.estado_nome
    FROM
        ev
    LEFT JOIN
        dw_public.dim_user AS du
            ON ev.sk_buyer = du.sk_user
    WHERE
        rn = 1
)
SELECT
    b.sk_buyer AS id_user,
    b.sk_offer AS id_driver,
    nome AS customer_name,
    email AS customer_email,
    telefone_principal AS customer_phone,
    'FS End of Process' AS campaign_step,
    'Buyer' AS customer_type,
    cpf AS customer_cpf,
    'true' AS campaign_type,
    'offer' AS driver_type,
    CASE
        WHEN rv.id_visitor IS NULL THEN 'Sale'
        ELSE 'Híbrido'
    END AS business_context
FROM
    base AS b
LEFT JOIN
    rent_visits AS rv
        ON rv.id_visitor = b.sk_buyer
        AND rv.dt_visit_rent BETWEEN (b.dt_event - INTERVAL '30' DAY) AND (b.dt_event + INTERVAL '30' DAY)
WHERE
    DATEDIFF(CURRENT_DATE, dt_event) = 114
    AND b.sk_user IS NOT NULL
