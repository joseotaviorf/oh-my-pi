WITH closing_infos AS (-- Get all ccv that were cancelled and were not rescued
    SELECT
        sk_offer
    FROM
        dw_sale.fact_closing_flows AS fcf
    WHERE
        sk_sale_agreement_cancelled_date != -1
    GROUP BY
        1
    HAVING
        MAX(sk_sale_agreement_cancelled_date) > MAX(sk_sale_agreement_rescued_date)
),
base AS (
    SELECT
        lf.sk_house_listing,
        lf.sk_first_listing_date,
        dd.date AS dt_first_publication,
        DATEDIFF(dd.date, CURRENT_DATE) AS days_since_first_publication,
        u.email AS pp_email,
        u.nome AS pp_nome,
        u.telefone_principal AS pp_tel,
        u.id AS pp_id,
        u.cpf
    FROM
        dw_sale.fact_listing_flows AS lf
    INNER JOIN
        dw_sale.fact_listings AS fl
            ON INT(fl.sk_sale_listing/1000) = lf.sk_house_listing/1000
    INNER JOIN
        dw_public.dim_user AS u
            ON u.sk_user = fl.sk_owner
    INNER JOIN
        dw_public.dim_date AS dd
            ON lf.sk_first_listing_date = dd.sk_date
    INNER JOIN
        dw_public.dim_region AS dr
            ON lf.sk_region = dr.sk_region
            AND dr.id_country = 1
),
rental_listing AS (
    SELECT
        dhl.ts_listing_version_start,
        fhl.sk_owner AS pp_id
    FROM
        dw_public.dim_house_listing dhl
    JOIN
        dw_public.fact_house_listings fhl
            ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE
        dhl.is_last_version = TRUE
        AND (DATEDIFF(dhl.ts_listing_version_start, CURRENT_DATE) <= 60 OR DATEDIFF(dhl.ts_listing_version_end, CURRENT_DATE) <= 30 OR dhl.ts_listing_version_end IS NULL)
        AND dhl.is_for_rent = TRUE
        AND dhl.status <> 'alugado'
        AND NOT(dhl.status = 'SUSPENDED' AND dhl.status_reason = 'RENTED')
        AND dhl.rent > 1
    GROUP BY
        1,2
),
ev AS (
    SELECT
        dd.date AS dt_event,
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer,
        ROW_NUMBER() OVER (PARTITION BY sf.sk_seller ORDER BY sf.sk_sale_agreement_signed_date DESC) AS rn
    FROM
        dw_sale.fact_sale_flows AS sf
    INNER JOIN
        dw_public.dim_date AS dd
            ON sf.sk_sale_agreement_signed_date = dd.sk_date
    INNER JOIN
        dw_sale.fact_offers AS fo
            ON sf.sk_sale_flow = fo.sk_sale_flow
    INNER JOIN
        dw_public.dim_region AS dr
            ON sf.sk_region = dr.sk_region
            AND dr.id_country = 1
    LEFT JOIN
        closing_infos AS ci
            ON fo.sk_offer = ci.sk_offer
    WHERE
        sf.sk_sale_agreement_signed_date >= 20200101
        AND ci.sk_offer IS NULL
)
SELECT DISTINCT
    b.pp_id AS id_user,
    sk_offer AS id_driver,
    pp_nome AS customer_name,
    pp_email AS customer_email,
    pp_tel AS customer_phone,
    'FS End of Process' AS campaign_step,
    'Seller' AS customer_type,
    cpf AS customer_cpf,
    'true' AS campaign_type,
    'offer' AS driver_type,
    CASE
        WHEN rl.pp_id IS NULL THEN 'Sale'
        ELSE 'Híbrido'
    END AS business_context
FROM
    ev
JOIN
    base AS b
        ON ev.sk_seller = CAST(b.pp_id AS BIGINT)
LEFT JOIN
    rental_listing rl
        ON rl.pp_id = b.pp_id
WHERE
    DATEDIFF(CURRENT_DATE, ev.dt_event) = 114
    AND rn=1
