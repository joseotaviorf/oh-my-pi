-- The cohort day is 10 days after the last rent-demand event with no follow-up.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH events AS (
    SELECT
        sk_tenant_prospect AS sk_client,
        dt.date AS event_date,
        IF(LEAD(dt.date, 1) OVER (PARTITION BY sk_tenant_prospect ORDER BY dt.date ASC) IS NOT NULL, TRUE, FALSE) AS has_next_event,
        MAX(IF(sk_event_type = 9, TRUE, FALSE)) AS is_contract_signed
    FROM
        dw_rent.fact_rent_demand_events AS fde
    JOIN
        dw_public.dim_date AS dt
            ON dt.sk_date = fde.sk_event_date
    WHERE
        fde.country_code = 'BR'
    GROUP BY
        1,
        2
),
visits_scheduled AS (
    SELECT DISTINCT
        id_visitor AS id_user
    FROM
        datalake_visit.visit_schedules AS db
    WHERE
        NOT (is_canceled OR id_succeed_schedule IS NOT NULL)
        AND DATE(ts_schedule_visit) >= DATE('{load_start_date}')
),
credit_evaluation AS (
    SELECT
        id_user,
        result,
        early_result,
        ROW_NUMBER() OVER (PARTITION BY id_user ORDER BY ts_created DESC) AS rn
    FROM
        datalake_docx_clean.credit_evaluation
    WHERE
        status = 'FINISHED'
),
credit_evaluation_explode AS (
    SELECT
        id_user,
        result,
        EXPLODE(FROM_JSON(early_result, 'ARRAY<STRING>')) AS early_result_exploded
    FROM
        credit_evaluation
    WHERE
        rn = 1
        AND early_result IS NOT NULL
),
credit_rejected AS (
    SELECT DISTINCT
        ce.id_user
    FROM
        credit_evaluation AS ce
    LEFT JOIN
        credit_evaluation_explode AS cee
            ON ce.id_user = cee.id_user
            AND COALESCE(ce.result, '') = COALESCE(cee.result, '')
    WHERE
        ce.rn = 1
        AND (
            ce.result = 'PRE_REJECTED'
            OR GET_JSON_OBJECT(early_result_exploded, '$.result') = 'REJECTED'
        )
),
insurance AS (
    SELECT DISTINCT
        id_tenant_ebdb AS id_user
    FROM
        datalake_rental_guarantee.guarantee
    WHERE
        guarantee_type = 'INSURANCE'
),
brokerage_only AS (
    SELECT DISTINCT
        sk_tenant_prospect AS id_user
    FROM
        dw_rent.fact_rent_demand_events AS fde
    INNER JOIN
        dw_rent.dim_house_listing AS dhl
            ON dhl.sk_house_listing = fde.sk_house_listing
    WHERE
        dhl.rental_administrator IN ('OWNER', 'THIRD_PARTY')
),
sale_flows AS (
    SELECT DISTINCT
        sk_buyer AS id_user
    FROM
        dw_sale.fact_sale_flows
    JOIN
        dw_public.dim_date AS dt
            ON dt.sk_date = GREATEST(
                sk_first_event_date,
                sk_first_tta_message_sent_date,
                sk_first_booking_created_date,
                sk_first_visit_completed_date,
                sk_first_offer_submitted_date,
                sk_first_offer_accepted_date,
                sk_first_offer_dismissed_date,
                sk_sale_agreement_created_date,
                sk_sale_agreement_signed_date,
                sk_sale_agreement_cancelled_date,
                sk_house_registry_ended_date
            )
    WHERE
        dt.sk_date > 0
        AND DATEDIFF(DATE('{load_start_date}'), dt.date) <= 10
),
crisis_users AS (
    SELECT DISTINCT
        ft.sk_user AS id_user
    FROM
        dw_customer_support.fact_tickets AS ft
    INNER JOIN
        dw_customer_support.dim_ticket AS dt
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dd
            ON dd.department = dt.group_name
    WHERE
        (
            dt.group_name IN (
                'Notificação Extrajudicial [CE] [POS] [BACK]',
                'Dados Bancários [CE] [POS] [BACK]',
                'CX ReclameAqui Adquiridas [CE] [POS] [BACK]'
            )
            OR dd.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
        )
        AND ft.sk_user <> -1
        AND ft.ts_solved IS NULL
),
users_to_exclude AS (
    SELECT
        id_user
    FROM
        visits_scheduled
    UNION
    SELECT
        id_user
    FROM
        credit_rejected
    UNION
    SELECT
        id_user
    FROM
        brokerage_only
    UNION
    SELECT
        id_user
    FROM
        sale_flows
    UNION
    SELECT
        id_user
    FROM
        crisis_users
    UNION
    SELECT
        id_user
    FROM
        insurance
),
customers AS (
    SELECT
        du.nome AS customer_name,
        du.email AS customer_email,
        du.telefone_principal AS customer_phone,
        'Lost IQ' AS campaign_step,
        'Inquilino' AS customer_type,
        du.cpf AS customer_cpf,
        e.sk_client AS id_user,
        'lost' AS campaign_type,
        '' AS driver_type,
        '' AS id_driver,
        DATE_ADD(e.event_date, 10) AS dt_cohort
    FROM
        events AS e
    JOIN
        dw_public.dim_user AS du
            ON du.sk_user = e.sk_client
    LEFT JOIN
        users_to_exclude AS u
            ON u.id_user = e.sk_client
    WHERE
        e.is_contract_signed IS FALSE
        AND e.has_next_event IS FALSE
        AND DATE_ADD(e.event_date, 10) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND u.id_user IS NULL
    UNION ALL
    SELECT
        'Teste Disparo' AS customer_name,
        'testes.disparos.5a@gmail.com' AS customer_email,
        '+5511123456789' AS customer_phone,
        'Lost IQ' AS campaign_step,
        'Inquilino' AS customer_type,
        '1234' AS customer_cpf,
        '1234' AS id_user,
        'lost' AS campaign_type,
        '' AS driver_type,
        '' AS id_driver,
        DATE('{load_start_date}') AS dt_cohort
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.lost_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.lost_iq
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT
    customers.customer_name,
    customers.customer_email,
    customers.customer_phone,
    customers.campaign_step,
    customers.customer_type,
    customers.customer_cpf,
    customers.id_user,
    customers.campaign_type,
    customers.driver_type,
    customers.id_driver,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    customers.dt_cohort,
    YEAR(customers.dt_cohort) AS year,
    MONTH(customers.dt_cohort) AS month,
    DAY(customers.dt_cohort) AS day
FROM
    customers
LEFT JOIN
    previous_dispatches AS pd
        ON customers.customer_email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(customers.dt_cohort, 90) AND customers.dt_cohort
