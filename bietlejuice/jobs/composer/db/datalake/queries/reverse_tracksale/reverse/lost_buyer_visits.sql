WITH buyers AS (
    SELECT 
        vb.id_visitor,
        MAX(CASE WHEN dt_created IS NOT NULL AND vb.visit_follow_up = 'VaiNegociar' THEN 1 ELSE 0 END) AS has_visit_completed
    FROM 
        dw_public.dim_booking vb 
    WHERE 
        vb.visit_intent = 'SALE'
        AND vb.type = 'Visita'
    GROUP BY 1
),
visits AS (
    SELECT 
        vb.sk_booking,
        vb.id_visitor,
        vb.id_property AS id_house,
        vb.id_agent,
        vb.id_attendant,
        vb.dt_created AS dt_booking_created,
        vb.dt_scheduling AS dt_visit,
        is_rescheduled,
        vb.status,
        vb.responsible,
        visit_follow_up,
        ROW_NUMBER() OVER (PARTITION BY id_visitor ORDER BY dt_scheduling DESC) AS rank_visitas
    FROM    
        dw_public.dim_booking vb 
    WHERE 
        vb.visit_intent = 'SALE'
        AND vb.type = 'Visita'
),
rent_visits AS (
	SELECT 
        id_visitor, 
        MAX(dt_scheduling) AS dt_visit_rent
    FROM 
        dw_public.dim_booking
    WHERE 
        visit_intent = 'RENT'
        AND type = 'Visita'
        AND visit_follow_up = 'VaiNegociar'
    GROUP BY 1
),
visits_ AS (
    SELECT 
        vb.sk_buyer,
        MAX(sk_visit_date) AS dt_last_schedule_visit
    FROM 
        dw_sale.fact_visits vb 
    GROUP BY 1
),
offers AS (
    SELECT 
        sk_buyer AS id_buyer,
        COALESCE(MAX(sk_offer_submitted_date),-1) AS dt_last_offer_sent
    FROM 
        dw_sale.fact_offers
    GROUP BY 1
),
sale_flows_events AS (
    SELECT
        sk_buyer,
        MAX(sk_sale_agreement_signed_date) AS dt_last_sale_agreement_signed,
        MAX(sk_house_registry_ended_date) AS dt_last_house_registry_ended
    FROM 
        dw_sale.fact_sale_flows
    GROUP BY 1
)
SELECT 
    nome AS customer_name,
    email AS customer_email,
    telefone_principal AS customer_phone,
    'Visita' AS campaign_step,
    'Buyer' AS customer_type,
    cpf AS customer_cpf,
    v.id_visitor AS id_user,
    'lost' AS campaign_type,
    'booking' AS driver_type,
    v.sk_booking AS id_driver,
    CASE WHEN rv.id_visitor is null THEN 'Sale' ELSE 'Híbrido' END AS business_context,
    NOW() AS ts_load
FROM 
    visits v
JOIN 
    buyers b 
        ON b.id_visitor = v.id_visitor 
JOIN 
    dw_public.dim_user du 
        ON du.sk_user = v.id_visitor 
LEFT JOIN 
    rent_visits rv 
        ON rv.id_visitor = v.id_visitor AND rv.dt_visit_rent BETWEEN DATE_SUB(v.dt_visit, 30) AND DATE_ADD(v.dt_visit, 30)
LEFT JOIN 
    visits_ v_ 
        ON v_.sk_buyer = v.id_visitor
LEFT JOIN 
    offers o 
        ON o.id_buyer = v_.sk_buyer 
LEFT JOIN 
    sale_flows_events sf 
        ON sf.sk_buyer = v.id_visitor 
WHERE 
    v.rank_visitas = 1
    AND v.is_rescheduled = 'False'
    AND DATEDIFF(current_date, v.dt_visit) = 20
    AND b.has_visit_completed = 0
    AND (TO_DATE(STRING(NULLIF(v_.dt_last_schedule_visit,-1)), 'yyyyMMdd') <= DATE(v.dt_visit) OR NULLIF(v_.dt_last_schedule_visit,-1) IS NULL)
    AND (TO_DATE(STRING(NULLIF(o.dt_last_offer_sent,-1)), 'yyyyMMdd') <= DATE(v.dt_visit) OR NULLIF(o.dt_last_offer_sent,-1) IS NULL)
    AND (TO_DATE(STRING(NULLIF(sf.dt_last_sale_agreement_signed,-1)), 'yyyyMMdd') <= DATE(v.dt_visit) OR NULLIF(sf.dt_last_sale_agreement_signed,-1) IS NULL)
    AND (TO_DATE(STRING(NULLIF(sf.dt_last_house_registry_ended,-1)), 'yyyyMMdd') <= DATE(v.dt_visit) OR NULLIF(sf.dt_last_house_registry_ended,-1) IS NULL)