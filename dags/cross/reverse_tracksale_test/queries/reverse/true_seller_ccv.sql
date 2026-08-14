-- The cohort day of an offer is 2 days after the sale agreement was signed.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH brazil_regions AS (
    SELECT
        sk_region
    FROM
        dw_public.dim_region
    WHERE
        id_country = 1
),
users AS (
    SELECT
        u.email,
        u.nome,
        u.telefone_principal,
        u.id,
        u.cpf
    FROM
        dw_public.dim_user AS u
),
ccvs AS (
    SELECT
        TO_DATE(STRING(NULLIF(fo.sk_sale_agreement_signed_date, -1)), 'yyyyMMdd') AS dt_event,
        fo.sk_house,
        fo.sk_offer,
        fo.sk_owner,
        fo.sk_buyer,
        DATE_ADD(TO_DATE(STRING(NULLIF(fo.sk_sale_agreement_signed_date, -1)), 'yyyyMMdd'), 2) AS dt_cohort
    FROM
        dw_sale.fact_offers AS fo
    INNER JOIN
        dw_sale.dim_offer AS df
            ON df.sk_offer = fo.sk_offer
    LEFT JOIN
        brazil_regions AS br
            ON fo.sk_region = br.sk_region
    WHERE
        fo.sk_sale_agreement_signed_date >= 20200101
        AND offer_flow = 'DEAL_MAKING'
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.true_seller_ccv
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.true_seller_ccv
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT DISTINCT
    nome AS customer_name,
    email AS customer_email,
    telefone_principal AS customer_phone,
    'CCV' AS campaign_step,
    'Seller' AS customer_type,
    cpf AS customer_cpf,
    u.id AS id_user,
    'true' AS campaign_type,
    'offer' AS driver_type,
    sk_offer AS id_driver,
    '' AS business_context,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    c.dt_cohort,
    YEAR(c.dt_cohort) AS year,
    MONTH(c.dt_cohort) AS month,
    DAY(c.dt_cohort) AS day
FROM
    ccvs AS c
INNER JOIN
    users AS u
        ON c.sk_owner = u.id
LEFT JOIN
    previous_dispatches AS pd
        ON u.email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(c.dt_cohort, 90) AND c.dt_cohort
WHERE
    c.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
