WITH brazil_regions AS (
    SELECT
        sk_region
    FROM
        dw_public.dim_region
    WHERE
        id_country = 1
),
base AS (
    SELECT
        lf.sk_house_listing,
        lf.sk_first_listing_date,
        dd.date AS dt_first_publication,
        DATEDIFF(current_date, dd.date) AS days_since_first_publication,
        u.email AS pp_email,
        u.nome AS pp_nome,
        u.telefone_principal AS pp_tel,
        u.id AS pp_id,
        u.cpf
    FROM
        dw_sale.fact_listing_flows lf
    JOIN dw_sale.fact_listings fl
        ON INT(fl.sk_sale_listing/1000) = lf.sk_house_listing/1000
    JOIN dw_public.dim_user u
        ON u.sk_user = fl.sk_owner
    JOIN dw_public.dim_date dd
        ON lf.sk_first_listing_date = dd.sk_date
    JOIN brazil_regions br
        ON lf.sk_region = br.sk_region
),
rental_listing AS (
    SELECT
        DISTINCT
        dhl.ts_listing_version_start,
        fhl.sk_owner AS pp_id
    FROM
        dw_public.dim_house_listing dhl
    JOIN
        dw_public.fact_house_listings fhl
            ON fhl.sk_house_listing = dhl.sk_house_listing
    WHERE
        dhl.is_last_version = true
        AND (DATEDIFF(current_date, dhl.ts_listing_version_start) <= 60 OR DATEDIFF(current_date, dhl.ts_listing_version_end) <= 30 OR dhl.ts_listing_version_end IS NULL)
        AND dhl.is_for_rent = true
        AND dhl.status <> 'alugado'
        AND dhl.rent > 1
),
ev AS (
    SELECT DISTINCT
        TO_DATE(STRING(sf.sk_house_registry_ended_date), 'yyyyMMdd') AS dt_event,
        sf.sk_house,
        fo.sk_offer,
        sf.sk_seller,
        sf.sk_buyer
    from
        dw_sale.fact_sale_flows sf
    JOIN
        dw_sale.fact_offers fo
            ON sf.sk_sale_flow = fo.sk_sale_flow
    JOIN brazil_regions br
        ON sf.sk_region = br.sk_region
    WHERE
        sf.sk_house_registry_ended_date >= 20200101
),
last_10_days AS (
    SELECT
        date,
        week_day,
        weekday_name,
        DATE_ADD(date, -10) AS last_10_days,
        LAG(date,10) OVER (ORDER BY date) AS last_10_working_days
    from
        dw_public.dim_date
    WHERE
        date <= current_date
        AND (week_day NOT IN (0,6) AND is_brz_holiday != 'Holiday')
)
SELECT DISTINCT
    pp_nome AS customer_name,
    pp_email AS customer_email,
    pp_tel AS customer_phone,
    'Registry' AS campaign_step,
    'Seller' AS customer_type,
    cpf AS customer_cpf,
    b.pp_id AS id_user,
    'true' AS campaign_type,
    'offer' AS driver_type,
    sk_offer AS id_driver,
    CASE
        WHEN rl.pp_id IS NULL
            THEN 'Sale'
        ELSE 'Híbrido'
    END AS business_context,
    ld.date
FROM
    ev
JOIN
    base b
        ON ev.sk_seller = CAST(b.pp_id AS BIGINT)
LEFT JOIN
    rental_listing rl
        ON rl.pp_id = b.pp_id
LEFT JOIN
    last_10_days ld
        ON ev.dt_event = ld.last_10_working_days
WHERE
    ld.date = current_date
