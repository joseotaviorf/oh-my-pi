WITH closing_infos AS (-- get all ccv with info about cancelled and rescued ccv
    SELECT
        cf.sk_offer,
        CASE
            WHEN ds.payment_model LIKE 'CCV_ASSISTANCE' THEN TRUE
            ELSE FALSE
        END AS ccv_assistance,
        CASE
            WHEN cf.sk_sale_agreement_cancelled_date != -1 THEN TRUE
            ELSE FALSE
        END AS ccv_cancelled,
        CASE
            WHEN cf.sk_sale_agreement_rescued_date != -1 THEN TRUE
            ELSE FALSE
        END AS ccv_rescued,
        payment_method,
        ts_house_registry_ended
    FROM
        dw_sale.fact_closing_flows AS cf
    LEFT JOIN
        dw_sale.dim_sale_agreement AS ds
            ON ds.sk_offer = cf.sk_offer
),
ev AS (
    SELECT DISTINCT
        dd.date AS dt_event,
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer,
        ci.payment_method,
        ci.ts_house_registry_ended
    FROM
        dw_sale.fact_sale_flows AS sf
    INNER JOIN
        dw_public.dim_region AS dr
            ON sf.sk_region = dr.sk_region
            AND dr.id_country = 1
    INNER JOIN
        dw_public.dim_date AS dd
            ON sf.sk_sale_agreement_signed_date = dd.sk_date
    INNER JOIN
        dw_sale.fact_offers AS fo
            ON sf.sk_sale_flow = fo.sk_sale_flow
    LEFT JOIN
        closing_infos AS ci
            ON fo.sk_offer = ci.sk_offer
    WHERE
        fo.ts_sale_agreement_signed >= DATE("2020-01-01")
        AND ci.ccv_cancelled = FALSE
        AND ci.ccv_rescued = FALSE
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
)
,
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
        du.estado_nome,
        ev.payment_method,
        ev.ts_house_registry_ended
    FROM
        ev
    LEFT JOIN
        dw_public.dim_user du
            ON ev.sk_buyer = du.sk_user
),
customers_info AS (
    SELECT
        nome AS customer_name,
        email AS customer_email,
        telefone_principal AS customer_phone,
        'FS End of Process' AS campaign_step,
        'Buyer' AS customer_type,
        cpf AS customer_cpf,
        b.sk_buyer AS id_user,
        'true' AS campaign_type,
        'offer' AS driver_type,
        b.sk_offer AS id_driver,
        b.payment_method,
        CASE
            WHEN rv.id_visitor IS null THEN 'Sale'
            ELSE 'Híbrido'
        END AS business_context,
        b.dt_event,
        b.ts_house_registry_ended
    FROM
        base AS b
    LEFT JOIN
        rent_visits AS rv
            ON rv.id_visitor = b.sk_buyer
            AND rv.dt_visit_rent BETWEEN (b.dt_event - INTERVAL '30' day)
            AND (b.dt_event + INTERVAL '30' day)
    WHERE
        b.sk_user IS NOT NULL
),
previous_sent_id_drivers AS (
    SELECT 
      id_driver
    FROM customers_info
    WHERE (
      (payment_method IS NULL OR payment_method LIKE 'FINANCED%')
      AND (ts_house_registry_ended IS NOT NULL AND DATE_ADD(dt_event, 114) <= CAST(ts_house_registry_ended AS TIMESTAMP))) 
      OR (
      (payment_method IS NULL OR payment_method LIKE 'CASH%') 
      AND (ts_house_registry_ended IS NOT NULL AND DATE_ADD(dt_event, 60) <= CAST(ts_house_registry_ended AS TIMESTAMP))
    ) OR (
      (payment_method IS NULL OR payment_method LIKE 'CASH%') 
      AND (dt_event <= DATE('2024-05-18'))
      AND (ts_house_registry_ended IS NULL OR DATE_ADD(CAST(ts_house_registry_ended AS TIMESTAMP), -2) <= DATE('2024-06-30'))
    )
  )
SELECT
    customer_name,
    customer_email,
    customer_phone,
    campaign_step,
    customer_type,
    customer_cpf,
    id_user,
    campaign_type,
    driver_type,
    id_driver,
    payment_method,
    ts_house_registry_ended,
    dt_event,
    business_context
FROM
    customers_info
WHERE
  ((ts_house_registry_ended IS NOT NULL AND DATEDIFF(CURRENT_DATE, ts_house_registry_ended) = 2)
  OR ((payment_method IS NULL OR payment_method LIKE 'FINANCED%') AND ts_house_registry_ended IS NULL AND DATEDIFF(CURRENT_DATE, dt_event) = 114)
  OR (payment_method LIKE 'CASH%' AND ts_house_registry_ended IS NULL AND DATEDIFF(CURRENT_DATE, dt_event) = 60))
  AND id_driver NOT IN (SELECT id_driver FROM previous_sent_id_drivers)
