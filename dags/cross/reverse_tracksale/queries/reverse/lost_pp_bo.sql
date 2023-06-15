WITH depublished_listings AS (
    SELECT
        fhl.sk_owner,
        fhl.sk_house_listing,
        fls.ts_status_start AS ts_depublication
    FROM 
        dw_public.fact_house_listings AS fhl
    INNER JOIN 
        dw_public.dim_house_listing AS dhl 
            ON dhl.sk_house_listing = fhl.sk_house_listing        
    INNER JOIN 
        dw_public.fact_house_listing_status AS fls 
            ON fls.sk_house_listing = fhl.sk_house_listing
            AND fls.status_history = 'despublicado'
    WHERE
        DATE(fls.ts_status_start) = DATE_SUB(current_date, 4)
        AND (dhl.house_unpublished_reason != 'OWNER_CONSEQUENCES_MANAGEMENT' OR dhl.house_unpublished_reason IS NULL)
        AND dhl.is_b2b = false
        AND dhl.is_for_sale = false
        AND dhl.version > 0
        AND dhl.country_code = 'BR'
        AND dhl.rental_administrator = 'OWNER' --Including only brokerage only for these metrics
    GROUP BY 1,2,3 
),
first_depublication AS (
    SELECT 
        sk_owner,
        MIN(ts_depublication) AS ts_first_depublication
    FROM 
        depublished_listings
    GROUP BY 1
),
crisis_users AS (
    SELECT 
        ft.sk_user
    FROM 
        dw_tickets.dim_ticket AS dt
    INNER JOIN 
        dw_tickets.fact_tickets AS ft 
            ON dt.sk_ticket  = ft.sk_ticket
    INNER JOIN
        dw_customer_support.dim_department AS dc
            ON dt.group_name = dc.department
    WHERE
        dc.team IN ('Casos Especiais','Proteção 5A','Ouvidoria','ReclameAqui')
        AND ft.sk_closed_date_local = -1
    GROUP BY 1
),
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
    LEFT JOIN 
        datalake_ebdb_clean.user_pro_owner AS po 
            ON dl.sk_owner = po.id_user
            AND po.is_active = true	
    WHERE
        uc.sk_user IS NULL
        AND po.is_active IS NULL
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
    '1234' AS id_user,
    'lost' AS campaign_type,
    'house_listing' AS driver_type,
    '1234' AS id_driver,
    NOW() AS ts_load