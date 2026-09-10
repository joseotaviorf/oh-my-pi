-- Cohort days are 17, 11, or 18 days after the offer event date, depending on the branch.
-- Anchoring on them (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH brazil_houses AS (
    SELECT
        id_house
    FROM
        dw_rent.dim_house_listing
    WHERE
        country_code = 'BR'
    GROUP BY
        1
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
ccv AS (
    SELECT
        sk_buyer,
        TO_DATE(MAX(sk_sale_agreement_signed_date), 'yyyyMMdd') AS dt_last_sale_agreement_signed
    FROM
        dw_sale.fact_sale_flows AS fs
    WHERE
        sk_sale_agreement_signed_date <> -1
    GROUP BY
        1
),
final AS (
    SELECT
        fo.ts_offer_submitted,
        fo.ts_offer_accepted,
        fo.ts_offer_dismissed,
        fo.ts_offer_rescued,
        dof.offer_status,
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer,
        ccv.dt_last_sale_agreement_signed,
        ROW_NUMBER() OVER (
            PARTITION BY
                sf.sk_buyer
            ORDER BY
                fo.ts_offer_submitted DESC
        ) AS rn,
        CASE
            WHEN rv.id_visitor IS NULL THEN 'Sale'
            ELSE 'Híbrido'
        END AS business_context
    FROM
        dw_sale.fact_sale_flows AS sf
    INNER JOIN
        brazil_houses AS dh
            ON sf.sk_house = dh.id_house
    LEFT JOIN
        dw_sale.fact_offers AS fo
            ON sf.sk_sale_flow = CONCAT(fo.sk_buyer, '_', fo.sk_house)
    LEFT JOIN
        dw_sale.dim_offer AS dof
            ON dof.sk_offer = fo.sk_offer
    LEFT JOIN
        ccv
            ON ccv.sk_buyer = sf.sk_buyer
            AND dt_last_sale_agreement_signed >= fo.ts_offer_submitted
    LEFT JOIN
        rent_visits AS rv
            ON rv.id_visitor = sf.sk_buyer
            AND rv.dt_visit_rent BETWEEN (
                fo.ts_offer_dismissed - INTERVAL '30' DAY
            ) AND (
                fo.ts_offer_dismissed + INTERVAL '30' DAY
            )
    WHERE
        fo.ts_offer_submitted IS NOT NULL
),
first_ AS (
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        DATE_ADD(DATE(ts_offer_dismissed), 17) AS dt_cohort
    FROM
        final
    WHERE
        rn = 1
        AND offer_status = 'OFFER_REJECTED'
),
second_ AS (
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        DATE_ADD(DATE(ts_offer_accepted), 11) AS dt_cohort
    FROM
        final
    WHERE
        rn = 1
        AND offer_status = 'OFFER_ACCEPTED'
        AND dt_last_sale_agreement_signed IS NULL
),
third_ AS (
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        DATE_ADD(DATE(ts_offer_submitted), 18) AS dt_cohort
    FROM
        final
    WHERE
        rn = 1
        AND ts_offer_accepted IS NULL
        AND ts_offer_dismissed IS NULL
        AND dt_last_sale_agreement_signed IS NULL
),
union_ AS (
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        dt_cohort
    FROM
        first_
    UNION ALL
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        dt_cohort
    FROM
        second_
    UNION ALL
    SELECT
        sk_buyer,
        sk_offer,
        business_context,
        dt_cohort
    FROM
        third_
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.lost_buyer_proposals
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.lost_buyer_proposals
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT
    du.nome AS customer_name,
    du.email AS customer_email,
    du.telefone_principal AS customer_phone,
    'Oferta' AS campaign_step,
    'Buyer' AS customer_type,
    du.cpf AS customer_cpf,
    v.sk_buyer AS id_user,
    'lost' AS campaign_type,
    'offer' AS driver_type,
    v.sk_offer AS id_driver,
    v.business_context,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    v.dt_cohort,
    YEAR(v.dt_cohort) AS year,
    MONTH(v.dt_cohort) AS month,
    DAY(v.dt_cohort) AS day
FROM
    union_ AS v
JOIN
    dw_public.dim_user AS du
        ON du.sk_user = v.sk_buyer
LEFT JOIN
    previous_dispatches AS pd
        ON du.email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(v.dt_cohort, 90) AND v.dt_cohort
WHERE
    v.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
