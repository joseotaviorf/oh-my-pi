WITH
  brazil_houses AS (
    SELECT DISTINCT
      sk_region
    FROM
      dw_public.dim_region
    WHERE
      id_country = 1 --- added to filter only BR business (excluding mexico)
  ),
  depublished_listings AS (
    SELECT DISTINCT
      fl.sk_owner,
      fl.sk_sale_listing,
      dl.ts_last_depublication,
      dl.ts_first_depublication,
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
      dw_sale.fact_listings fl
    JOIN 
      dw_sale.dim_listing dl 
        ON dl.sk_sale_listing = fl.sk_sale_listing
    INNER JOIN 
      brazil_houses br
        ON fl.sk_region = br.sk_region --- added to filter only BR business (excluding mexico)
    LEFT JOIN 
      dw_public.dim_house_listing dhl 
        ON dhl.id_house = dl.sk_house
    WHERE
      date_diff (CURRENT_DATE, DATE(dl.ts_last_depublication)) = 20
      AND (
        unpublished_reason != 'OWNER_CONSEQUENCES_MANAGEMENT'
        OR unpublished_reason != 'DUPLICATED_HOUSE'
        OR unpublished_reason != 'OWNER_MISSED_NEGOTIATIONS_LIMIT_REACHED'
        OR unpublished_reason IS NULL
      )
      AND dhl.is_for_rent = FALSE -- and substring(fl.sk_sale_listing, 10, 12) != '000'
  ),
  first_depublication AS (
    SELECT
      sk_owner,
      MIN(ts_first_depublication) AS ts_first_depublication
    FROM
      depublished_listings
    GROUP BY
      1
  ),
  crisis_users AS (
    SELECT
      ft.sk_user
    FROM
      dw_customer_support.dim_ticket dt
    INNER JOIN 
      dw_customer_support.fact_tickets ft 
        ON dt.sk_ticket = ft.sk_ticket
    INNER JOIN 
      dw_customer_support.dim_department dc 
        ON dt.group_name = dc.department --department é o antigo aux_canal
    WHERE
      dc.team IN ('Casos Especiais', 'Ouvidoria', 'Proteção 5A', 'ReclameAqui', 'Evictions') -- exclude contracts from these areas
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
      dl.business_context
    FROM
      depublished_listings dl
    INNER JOIN 
      first_depublication fd 
        ON dl.sk_owner = fd.sk_owner
        AND dl.ts_last_depublication = fd.ts_first_depublication
    LEFT JOIN 
      crisis_users uc 
        ON dl.sk_owner = uc.sk_user
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
  o.sk_sale_listing AS id_driver,
  business_context
FROM
  owners o
INNER JOIN 
  dw_public.dim_user u 
    ON u.sk_user = o.sk_owner