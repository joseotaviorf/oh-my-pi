-- Benvi PP Lost: landlords who unpublished listings on D-4 by reason not of consequence management, excluding B2B and forsale
WITH depublished_listings AS (
    SELECT
        fhl.sk_owner,
        fhl.sk_house_listing,
        fls.ts_status_start AS ts_depublication
    FROM
        dw_rent.fact_house_listings AS fhl -- considering as owner only users with published listings
    INNER JOIN
        dw_rent.dim_house_listing AS dhl
            ON dhl.sk_house_listing = fhl.sk_house_listing
            AND dhl.country_code = 'MX'
            AND dhl.version > 0 -- exclusing listings for edition before publishing
    INNER JOIN
        dw_rent.fact_house_listing_status AS fls
            ON fls.sk_house_listing = fhl.sk_house_listing
            AND fls.status_history IN ('despublicado', 'UNPUBLISHED') -- listing status modification is depublishing
    WHERE
        DATE(fls.ts_status_start) = DATE_ADD(CURRENT_DATE(), -4) -- SELECT listings depublished on D-4
        AND (dhl.house_unpublished_reason != 'OWNER_CONSEQUENCES_MANAGEMENT' OR dhl.house_unpublished_reason IS NULL) -- excluding consequence management
        AND dhl.is_b2b = FALSE -- excluding B2B listings
        AND dhl.is_for_sale = FALSE -- excluding listings for sale
    GROUP BY 1, 2, 3
),
-- considering the first depublication on D-4 for each owner
first_depublication AS (
    SELECT
        sk_owner,
        MIN(ts_depublication) AS ts_first_depublication
    FROM
        depublished_listings
    GROUP BY 1
),
-- avoid users which experience ongoing crisis, there is crisis tickets not closed yet
crisis_users AS (
    SELECT
        ft.sk_user
    FROM
        dw_tickets.dim_ticket AS dt
    INNER JOIN
        dw_tickets.fact_tickets AS ft
            ON dt.sk_ticket  = ft.sk_ticket
            AND ft.sk_closed_date_local = -1
    INNER JOIN
        dw_customer_support.dim_department AS dc
            ON dt.group_name = dc.department
            AND dc.team IN ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui') -- exclude users FROM these areas (crisis)
    GROUP BY 1
),
-- get the corresponding city of the first depublicated listing for each owner
owners AS (
    SELECT
        dl.sk_owner,
        dl.sk_house_listing
    FROM
        depublished_listings AS dl
    INNER JOIN
        first_depublication AS fd
            ON dl.sk_owner = fd.sk_owner
            AND dl.ts_depublication = fd.ts_first_depublication
    LEFT JOIN
        crisis_users AS uc
            ON uc.sk_user = dl.sk_owner
    WHERE
        uc.sk_user IS NULL -- exclude users with ongoing crisis ticket
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
    o.sk_house_listing AS id_driver,
    NOW() AS ts_load
FROM
    owners AS o
INNER JOIN
    dw_public.dim_user AS u
        ON u.sk_user = o.sk_owner
UNION ALL
SELECT
    'Teste Disparo' AS customer_name,
    'testes.disparos.5a@gmail.com' AS customer_email,
    '+5511123456789' AS customer_phone,
    'PP Lost' AS campaign_step,
    'Proprietário' AS customer_type,
    '1234' AS customer_cpf,
    1234 AS id_user,
    'lost' AS campaign_type,
    'house_listing' AS driver_type,
    1234 AS id_driver,
    NOW() AS ts_load
