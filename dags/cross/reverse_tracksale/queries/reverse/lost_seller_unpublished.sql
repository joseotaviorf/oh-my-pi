WITH brazil_regions AS (
    SELECT
        DISTINCT sk_region
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
        CASE
            WHEN (dhl.is_for_rent = true AND dhl.is_for_sale = true) THEN 'Hibrido'
            WHEN (dhl.is_for_rent = false AND dhl.is_for_sale = true) THEN 'Sale'
            WHEN (dhl.is_for_rent = true AND dhl.is_for_sale = false) THEN 'Rent'
            ELSE ''
        END AS business_context
    FROM
        dw_sale.fact_listings fl
    JOIN
        dw_sale.dim_listing dl
            ON dl.sk_sale_listing = fl.sk_sale_listing
    INNER JOIN
        brazil_regions br
            ON fl.sk_region = br.sk_region
    LEFT JOIN
        dw_rent.dim_house_listing dhl
            ON dhl.id_house = dl.sk_house
    WHERE
        DATEDIFF(current_date, DATE(dl.ts_last_depublication)) = 4
        AND (unpublished_reason != 'OWNER_CONSEQUENCES_MANAGEMENT' OR unpublished_reason IS NULL)
        AND dhl.is_for_rent = false
),
first_depublication AS (
    SELECT
        sk_owner,
        MIN(ts_first_depublication) AS ts_first_depublication
    FROM depublished_listings
    GROUP BY 1
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
            ) OR dd.team IN ('Casos Especiais', 'Ouvidoria', 'ReclameAqui', 'Evictions')
        )
        AND ft.sk_user <> -1
        AND ft.ts_solved IS NULL
),
owners AS (
    SELECT
        dl.sk_owner,
        dl.sk_sale_listing,
        dl.business_context
    FROM
        depublished_listings dl
    INNER JOIN
        first_depublication fd
            ON dl.sk_owner = fd.sk_owner
            AND dl.ts_last_depublication = fd.ts_first_depublication
    LEFT JOIN
        crisis_users uc
            ON uc.sk_user = dl.sk_owner
    WHERE uc.sk_user IS NULL -- exclude users with ongoing crisis ticket
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
	business_context,
    NOW() AS ts_load
FROM
    owners o
INNER JOIN
    dw_public.dim_user u
        ON u.sk_user = o.sk_owner
