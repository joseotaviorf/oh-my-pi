-- The cohort day is 20 days after the listing was last unpublished.
-- Anchoring on it (instead of CURRENT_DATE) keeps the result reproducible on backfills.
WITH brazil_houses AS (
    SELECT DISTINCT
        sk_region
    FROM
        dw_public.dim_region
    WHERE
        id_country = 1
),
depublished_listings AS (
    SELECT DISTINCT
        fl.sk_owner,
        fl.sk_sale_listing,
        dl.ts_last_depublication,
        dl.ts_first_depublication,
        DATE_ADD(DATE(dl.ts_last_depublication), 20) AS dt_cohort,
        CASE
            WHEN (
                dhl.is_for_rent = TRUE
                AND dhl.is_for_sale = TRUE
            ) THEN 'Hibrido'
            WHEN (
                dhl.is_for_rent = FALSE
                AND dhl.is_for_sale = TRUE
            ) THEN 'Sale'
            WHEN (
                dhl.is_for_rent = TRUE
                AND dhl.is_for_sale = FALSE
            ) THEN 'Rent'
            ELSE ''
        END AS business_context
    FROM
        dw_sale.fact_listings AS fl
    JOIN
        dw_sale.dim_listing AS dl
            ON dl.sk_sale_listing = fl.sk_sale_listing
    INNER JOIN
        brazil_houses AS br
            ON fl.sk_region = br.sk_region
    LEFT JOIN
        dw_rent.dim_house_listing AS dhl
            ON dhl.id_house = dl.sk_house
    WHERE
        (
            unpublished_reason != 'OWNER_CONSEQUENCES_MANAGEMENT'
            OR unpublished_reason != 'DUPLICATED_HOUSE'
            OR unpublished_reason != 'OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'
            OR unpublished_reason IS NULL
        )
        AND dhl.is_for_rent = FALSE
),
first_depublication AS (
    SELECT
        sk_owner,
        dt_cohort,
        MIN(ts_first_depublication) AS ts_first_depublication
    FROM
        depublished_listings
    GROUP BY
        1,
        2
),
crisis_users AS (
    SELECT
        ft.sk_user
    FROM
        dw_customer_support.dim_ticket AS dt
    INNER JOIN
        dw_customer_support.fact_tickets AS ft
            ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dc
            ON dt.group_name = dc.department
    WHERE
        dc.team IN (
            'Casos Especiais',
            'Ouvidoria',
            'Proteção 5A',
            'ReclameAqui',
            'Evictions'
        )
        AND (
            dt.status <> 'Closed'
            AND dt.status <> 'Solved'
        )
    GROUP BY
        1
),
owners AS (
    SELECT
        dl.sk_owner,
        dl.sk_sale_listing,
        dl.business_context,
        dl.dt_cohort
    FROM
        depublished_listings AS dl
    INNER JOIN
        first_depublication AS fd
            ON dl.sk_owner = fd.sk_owner
            AND dl.dt_cohort = fd.dt_cohort
            AND dl.ts_last_depublication = fd.ts_first_depublication
    LEFT JOIN
        crisis_users AS uc
            ON dl.sk_owner = uc.sk_user
    WHERE
        uc.sk_user IS NULL
),
previous_dispatches AS (
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        reverse_tracksale_test.lost_seller_unpublished
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
    UNION
    SELECT DISTINCT
        customer_email,
        MAKE_DATE(year, month, day) AS dt_partition
    FROM
        datalake_tracksale_reverse.lost_seller_unpublished
    WHERE
        is_dispatched = TRUE
        AND customer_email IS NOT NULL
        AND MAKE_DATE(year, month, day) >= DATE_SUB(DATE('{load_start_date}'), 90)
)
SELECT
    u.nome AS customer_name,
    u.email AS customer_email,
    u.telefone_principal AS customer_phone,
    'PP Lost' AS campaign_step,
    'Proprietário' AS customer_type,
    u.cpf AS customer_cpf,
    u.sk_user AS id_user,
    'lost' AS campaign_type,
    'house_listing' AS driver_type,
    o.sk_sale_listing AS id_driver,
    o.business_context,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS is_dispatched,
    CASE
        WHEN pd.customer_email IS NOT NULL THEN CAST(DATE('{load_start_date}') AS TIMESTAMP)
        ELSE CAST(NULL AS TIMESTAMP)
    END AS ts_dispatched,
    o.dt_cohort,
    YEAR(o.dt_cohort) AS year,
    MONTH(o.dt_cohort) AS month,
    DAY(o.dt_cohort) AS day
FROM
    owners AS o
INNER JOIN
    dw_public.dim_user AS u
        ON u.sk_user = o.sk_owner
LEFT JOIN
    previous_dispatches AS pd
        ON u.email = pd.customer_email
        AND pd.dt_partition BETWEEN DATE_SUB(o.dt_cohort, 90) AND o.dt_cohort
WHERE
    o.dt_cohort BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
