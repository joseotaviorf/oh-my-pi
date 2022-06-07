WITH brazil_regions AS (
    SELECT
        sk_region
    FROM
        dw_public.dim_region
    WHERE
        id_country = 1
),
ev AS (
    SELECT DISTINCT
        TO_DATE(STRING(sf.sk_house_registry_ended_date), 'yyyyMMdd') AS dt_event,
        ROW_NUMBER() OVER (PARTITION BY sf.sk_buyer ORDER BY sf.sk_house_registry_ended_date) AS rn,
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer
    FROM
        dw_sale.fact_sale_flows sf
    INNER JOIN
        brazil_regions rf
            ON sf.sk_region = rf.sk_region
    JOIN
        dw_sale.fact_offers fo
            ON sf.sk_sale_flow = fo.sk_sale_flow
    WHERE
        sf.sk_house_registry_ended_date >= 20200101
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
    WHERE rn = 1
),
last_10_days AS (
    SELECT
        date,
        week_day,
        weekday_name,
        DATE_ADD(date, 10) AS last_10_days,
        LAG(date,10) OVER (ORDER BY DATE) AS last_10_working_days
    FROM
        dw_public.dim_date
    WHERE
        date <= current_date
        AND (week_day NOT IN (0,6)
        AND is_brz_holiday != 'Holiday')
)
SELECT
    nome AS customer_name,
    email AS customer_email,
    telefone_principal AS customer_phone,
    'Registro' AS campaign_step,
    'Buyer' AS customer_type,
    cpf AS customer_cpf,
    b.sk_buyer AS id_user,
    'true' AS campaign_type,
    'offer' AS driver_type,
    b.sk_offer AS id_driver,
    CASE
        WHEN rv.id_visitor IS NULL
            THEN 'Sale'
        ELSE 'Híbrido'
    END AS business_context
FROM
    base b
LEFT JOIN
    rent_visits rv
        ON rv.id_visitor = b.sk_buyer
        AND rv.dt_visit_rent BETWEEN DATE_ADD(b.dt_event, -30) AND DATE_ADD(b.dt_event, 30)
LEFT JOIN
    last_10_days ld
        ON b.dt_event = ld.last_10_working_days
WHERE ld.date = current_date