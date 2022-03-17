WITH ev AS (
  SELECT DISTINCT
      TO_DATE(STRING(COALESCE(NULLIF(fo.sk_offer_dismissed_date,-1),NULLIF(fo.sk_offer_submitted_date,-1))), 'yyyyMMdd') AS dt_event,
      dof.offer_status,
      ROW_NUMBER() OVER (PARTITION BY sf.sk_buyer ORDER BY NULLIF(fo.sk_offer_dismissed_date,-1)) AS rn,
      sf.sk_house,
      fo.sk_offer,
      sf.sk_seller,
      sf.sk_buyer
  FROM
      dw_sale.fact_sale_flows sf
  JOIN 
      dw_sale.fact_offers fo
          ON sf.sk_sale_flow = fo.sk_sale_flow
  JOIN 
      dw_sale.dim_offer dof
        ON dof.sk_offer = fo.sk_offer 
          AND dof.offer_status IN ('Offer Rejected', 'OFFER_REJECTED')
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
        ev.sk_buyer AS id_buyer,
        ev.dt_event,
        ev.sk_offer AS id_offer,
        du.sk_user AS id_user,
        du.cpf,
        du.nome, 
        du.email, 
        du.telefone_principal, 
        du.cidade, 
        du.estado_nome
    FROM 
        ev 
    JOIN 
        dw_public.dim_user du 
            ON ev.sk_buyer = du.sk_user
    WHERE 
        rn = 1
),
visits AS (
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
        MAX(sk_offer_submitted_date) AS dt_last_offer_sent
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
    'Oferta Recusada' AS campaign_step,
    'Buyer' AS customer_type,
    cpf AS customer_cpf,
    b.id_buyer AS id_user,
    'lost' AS campaign_type,
    'offer' AS driver_type,
    b.id_offer AS id_driver,
    CASE WHEN rv.id_visitor IS NULL THEN 'Sale' ELSE 'Híbrido' END AS business_context,
    NOW() AS ts_load
FROM 
    base b 
LEFT JOIN 
    rent_visits rv 
        ON rv.id_visitor = b.id_buyer AND rv.dt_visit_rent BETWEEN DATE_SUB(b.dt_event, 30) AND DATE_ADD(b.dt_event, 30)
JOIN 
    visits v 
        ON v.sk_buyer = b.id_buyer AND (TO_DATE(STRING(NULLIF(v.dt_last_schedule_visit,-1)), 'yyyyMMdd') <= b.dt_event OR NULLIF(v.dt_last_schedule_visit,-1) IS NULL)
JOIN 
    offers o 
        ON o.id_buyer = b.id_buyer AND (TO_DATE(STRING(NULLIF(o.dt_last_offer_sent, -1)), 'yyyyMMdd') <= b.dt_event OR NULLIF(o.dt_last_offer_sent, -1) IS NULL)
JOIN 
    sale_flows_events sf 
        ON sf.sk_buyer = b.id_buyer 
            AND (TO_DATE(STRING(NULLIF(sf.dt_last_sale_agreement_signed,-1)), 'yyyyMMdd') <= b.dt_event OR NULLIF(sf.dt_last_sale_agreement_signed,-1) IS NULL)
            AND (TO_DATE(STRING(NULLIF(sf.dt_last_house_registry_ended,-1)), 'yyyyMMdd') <= b.dt_event OR NULLIF(sf.dt_last_house_registry_ended,-1) IS NULL)
WHERE
    DATEDIFF(current_date, b.dt_event) = 26