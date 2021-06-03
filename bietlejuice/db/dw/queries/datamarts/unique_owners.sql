WITH proprietarios AS(
    SELECT
        distinct
            du.sk_user AS sk_user,
            du.nome AS nome,
            du.email AS email,
            du.telefone_principal AS telefone_principal
    FROM
        dim_user du

),
leads AS (
    WITH leads_with_business_context AS (
        (SELECT
            fhlf.sk_lead AS sk_lead,
            fhlf.sk_house_listing AS sk_house_listing,
            SUBSTRING(sk_house_listing, 1, 9) AS id_house,
            fhlf.sk_lead_date AS sk_lead_date,
            fhlf.sk_prospect_date AS sk_prospect_date,
            fhlf.sk_qualified_date AS sk_qualified_date,
            fhlf.sk_opportunity_date AS sk_opportunity_date,
            fhlf.sk_first_listing_date AS sk_first_listing_date,
            dl.telefone_anunciante AS telefone_anunciante,
            fhlf.mkt_origin AS mkt_origin,
            fhlf.mkt_channel AS mkt_channel,
            fhlf.mkt_medium AS mkt_medium,
            fhlf.mkt_source AS mkt_source,
            'sale' AS business_context
        FROM
            dim_lead dl
        JOIN
            sale.fact_listing_flows fhlf
                ON fhlf.sk_lead = dl.sk_lead
        WHERE sk_lead_date > 0
        )

        UNION ALL

        (SELECT
            fhlf.sk_lead AS sk_lead,
            fhlf.sk_house_listing AS sk_house_listing,
            SUBSTRING(sk_house_listing, 1, 9) AS id_house,
            fhlf.sk_lead_date AS sk_lead_date,
            fhlf.sk_prospect_date AS sk_prospect_date,
            fhlf.sk_qualified_date AS sk_qualified_date,
            fhlf.sk_opportunity_date AS sk_opportunity_date,
            fhlf.sk_first_listing_date AS sk_first_listing_date,
            dl.telefone_anunciante AS telefone_anunciante,
            fhlf.mkt_origin AS mkt_origin,
            fhlf.mkt_channel AS mkt_channel,
            fhlf.mkt_medium AS mkt_medium,
            fhlf.mkt_source AS mkt_source,
            'rent' AS business_context
        FROM
            dim_lead dl
        JOIN
            fact_house_listing_flows fhlf
                ON fhlf.sk_lead = dl.sk_lead
        WHERE sk_lead_date > 0
        )
    ),
    count_context AS
        (SELECT
            id_house AS id_house_cc,
            COUNT(distinct business_context) context_count
        FROM leads_with_business_context
        WHERE id_house > 0
        GROUP BY 1
        ),

    ranking AS
        (SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY sk_lead_date ASC) AS first_lead
        FROM leads_with_business_context lbc
        LEFT JOIN count_context cc
            ON  cc.id_house_cc = lbc.id_house
        WHERE id_house > 0
        )

    (SELECT
        *
    FROM leads_with_business_context
    WHERE id_house NOT IN (SELECT id_house FROM ranking)
    )
    UNION ALL
    (SELECT
        sk_lead,
        sk_house_listing,
        id_house,
        sk_lead_date,
        sk_prospect_date,
        sk_qualified_date,
        sk_opportunity_date,
        sk_first_listing_date,
        telefone_anunciante,
        mkt_origin,
        mkt_channel,
        mkt_medium,
        mkt_source,
        CASE
            WHEN context_count = 2 THEN 'hybrid'
            ELSE business_context
        END AS business_context
    FROM ranking
    WHERE first_lead = 1
    )
),
house_listings AS (
    SELECT
        distinct
            dhl.id_house AS id_house,
            fhl.sk_owner AS sk_owner
    FROM
        dim_house_listing dhl
    JOIN
        fact_house_listings fhl
            ON dhl.sk_house_listing = fhl.sk_house_listing

),
visao_pp AS(
    SELECT
        l.sk_lead AS sk_lead,
        l.sk_house_listing AS sk_house_listing,
        l.id_house,
        hl.sk_owner AS sk_user,
        p.nome AS nome,
        p.email AS email,
        CASE
            WHEN p.telefone_principal IS NULL THEN l.telefone_anunciante
            ELSE p.telefone_principal
        END AS telefone,
        l.mkt_origin AS mkt_origin,
        l.mkt_channel AS mkt_channel,
        l.mkt_medium AS mkt_medium,
        l.mkt_source AS mkt_source,
        l.business_context AS business_context,
        l.sk_lead_date,
        l.sk_prospect_date,
        l.sk_qualified_date,
        l.sk_opportunity_date,
        l.sk_first_listing_date
    FROM
        leads l
    LEFT JOIN
        house_listings hl
            ON l.id_house = hl.id_house
    LEFT JOIN
        proprietarios p
            ON hl.sk_owner = p.sk_user

)
SELECT
    SHA2(telefone, 256) AS id_proprietario,
    * ,
    min(sk_lead_date) OVER (PARTITION BY telefone) sk_date_cadastro
FROM visao_pp
ORDER BY 1
