-- The cohort day is 2 days after house registry ended (CRI FIM).
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH closing_infos AS (
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
        ds.payment_method AS payment_method,
        sof.dt_house_registry_ended AS ts_house_registry_ended
    FROM
        dw_sale.fact_closing_flows AS cf
    LEFT JOIN
        dw_sale.dim_sale_agreement AS ds
            ON ds.sk_offer = cf.sk_offer
    LEFT JOIN
        datalake_sale_offer_flows.sale_offer_flows AS sof
            ON cf.sk_offer = sof.id_offer
),
ev AS (
    SELECT DISTINCT
        DATE(sof.dt_sale_agreement_signed) AS dt_event,
        sof.id_house AS sk_house,
        fo.sk_offer,
        sof.id_seller AS sk_seller,
        sof.id_buyer AS sk_buyer,
        ci.payment_method,
        ci.ts_house_registry_ended,
        DATE_ADD(DATE(ci.ts_house_registry_ended), 2) AS dt_cohort
    FROM
        datalake_sale_offer_flows.sale_offer_flows AS sof
    INNER JOIN
        dw_sale.fact_offers AS fo
            ON sof.id_offer = fo.sk_offer
    INNER JOIN
        dw_public.dim_region AS dr
            ON fo.sk_region = dr.sk_region
            AND dr.id_country = 1
    LEFT JOIN
        closing_infos AS ci
            ON fo.sk_offer = ci.sk_offer
    WHERE
        fo.ts_sale_agreement_signed >= DATE('2020-01-01')
        AND sof.dt_sale_agreement_signed IS NOT NULL
        AND ci.ccv_cancelled = FALSE
        AND ci.ccv_rescued = FALSE
),
rent_visits AS (
    SELECT
        id_visitor,
        MAX(ts_visit) AS dt_visit_rent
    FROM
        datalake_visit.visits
    WHERE
        business_context = 'RENT'
        AND is_completed
    GROUP BY
        1
),
base AS (
    SELECT
        ev.sk_buyer,
        ev.dt_event,
        ev.sk_offer,
        ev.dt_cohort,
        du.sk_user,
        du.cpf,
        du.nome,
        du.email,
        du.telefone_principal,
        ev.payment_method,
        ev.ts_house_registry_ended
    FROM
        ev
    LEFT JOIN
        dw_public.dim_user AS du
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
            WHEN rv.id_visitor IS NULL THEN 'Sale'
            ELSE 'Híbrido'
        END AS business_context,
        b.dt_event,
        b.ts_house_registry_ended,
        b.dt_cohort
    FROM
        base AS b
    LEFT JOIN
        rent_visits AS rv
            ON rv.id_visitor = b.sk_buyer
            AND rv.dt_visit_rent BETWEEN (b.dt_event - INTERVAL '30' DAY)
            AND (b.dt_event + INTERVAL '30' DAY)
    WHERE
        b.sk_user IS NOT NULL
        AND b.ts_house_registry_ended IS NOT NULL
        AND b.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
previous_sent_id_drivers AS (
    SELECT
        id_driver
    FROM
        customers_info
    WHERE
        (
            (payment_method IS NULL OR payment_method LIKE 'FINANCED%')
            AND ts_house_registry_ended IS NOT NULL
            AND DATE_ADD(dt_event, 114) <= CAST(ts_house_registry_ended AS TIMESTAMP)
            AND DATE_ADD(dt_event, 114) <= CAST('2024-10-24' AS DATE)
        )
        OR
        (
            (payment_method IS NULL OR payment_method LIKE 'CASH%')
            AND ts_house_registry_ended IS NOT NULL
            AND DATE_ADD(dt_event, 60) <= CAST('2024-10-24' AS DATE)
            AND DATE_ADD(dt_event, 60) <= CAST(ts_house_registry_ended AS TIMESTAMP)
        )
),
customers AS (
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
        business_context,
        dt_cohort
    FROM
        customers_info
    WHERE
        id_driver NOT IN (
            SELECT
                id_driver
            FROM
                previous_sent_id_drivers
        )
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.buyer_end_of_process
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.buyer_end_of_process
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
    customers.business_context,
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
