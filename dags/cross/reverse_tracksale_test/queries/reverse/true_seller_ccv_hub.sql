-- The cohort day of an offer is 1 day after the sale agreement was signed.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
-- Customers already dispatched by the legacy reverse_tracksale DAG for this campaign within
-- the last 24h (reference cohort day and the day before) keep is_dispatched = TRUE so the
-- migration DAGs do not send them again while both pipelines can still run.
-- ts_dispatched is null on load; reverse_tracksale_access sets it to current_timestamp() on POST.
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
    	DATE_ADD(TO_DATE(STRING(NULLIF(fo.sk_sale_agreement_signed_date, -1)), 'yyyyMMdd'), 1) AS dt_cohort
    FROM
        dw_sale.fact_offers fo
    INNER JOIN
        dw_sale.dim_offer df
            ON df.sk_offer = fo.sk_offer
    JOIN
        brazil_regions br
            ON fo.sk_region = br.sk_region
    WHERE
    	fo.sk_sale_agreement_signed_date >= 20200101
    	AND offer_flow = 'HUB'
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.true_seller_ccv_hub
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
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
    'Sale' AS business_context,
    '' AS cidade,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CAST(NULL AS TIMESTAMP) AS ts_dispatched,
    c.dt_cohort,
    YEAR(c.dt_cohort) AS year,
    MONTH(c.dt_cohort) AS month,
    DAY(c.dt_cohort) AS day
FROM
    ccvs AS c
INNER JOIN
    users u
        ON c.sk_owner = u.id
LEFT JOIN
    previous_dispatches AS pd
        ON u.email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(c.dt_cohort, 1) AND c.dt_cohort
WHERE
    c.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
