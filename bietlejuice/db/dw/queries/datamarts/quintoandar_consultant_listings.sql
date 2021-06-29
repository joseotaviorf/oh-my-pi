WITH check_ciq_full AS (
    SELECT
        JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS id_house_external
    FROM
        datalake_big_agent_clean_prod.House
    INNER JOIN
        datalake_big_agent_clean_prod.Agency
            ON Agency.id_house = house.id
    GROUP BY
        JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    HAVING
        COUNT(JSON_EXTRACT_PATH_TEXT( House.details, 'houseExternalId'))  > 1
),
last_enrollment AS (
    SELECT
        id_house,
        MAX(id_enrollment) AS id_enrollment
    FROM
        datalake_big_agent_clean_prod.Agency
    GROUP BY 1
),
house_change AS
(
    SELECT
        id
    FROM
        datalake_ebdb_raw_prod.imovel_aud
    WHERE
        usuarioquecadastrou_mod IS TRUE
        OR forsale_mod IS TRUE
),
quintoandar_consultant_listings as
((
    SELECT
        dhl.sk_house_listing,
        CAST(JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS BIGINT) AS id_house,
        CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT) AS sk_quintoandar_consultant,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND  program.name='CIQ_FULL' AS is_ciq_origin,
        CASE
            WHEN lf.mkt_origin = 'CIQ'  THEN TRUE
            ELSE program.name='CIQ_MANAGER'
        END AS is_account_manager,
        CASE
            WHEN ccf.id_house_external IS NOT NULL THEN 'CIQ_FULL'
            ELSE program.name
        END AS type_big_agent,
        'RENT' AS businesscontext
    FROM
        datalake_big_agent_clean_prod.House
    LEFT JOIN
        last_enrollment le
            ON le.id_house =House.id
    LEFT JOIN
        datalake_big_agent_clean_prod.enrollment
            ON enrollment.id=le.id_enrollment
    LEFT JOIN
        datalake_big_agent_clean_prod.Agent
            ON agent.id=enrollment.id_agent
    LEFT JOIN
        datalake_big_agent_clean_prod.program
            ON program.id=enrollment.id_program
    LEFT JOIN
        dim_house_listing dhl
            ON dhl.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN
        fact_house_listing_flows lf
            ON dhl.id_house = lf.sk_house_listing/1000
    LEFT JOIN
        check_ciq_full ccf
            ON ccf.id_house_external=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    )
    UNION
    (
    SELECT DISTINCT
        dl.sk_sale_listing,
        i.id AS id_house,
        pa.id_user AS sk_quintoandar_consultant,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AS is_ciq_origin,
        CASE
            WHEN lf.mkt_origin = 'CIQ'  THEN TRUE
            ELSE FALSE
        END AS is_account_manager,
        'CIQ_FULL' AS type_big_agent,
        'SALE' AS businesscontext
    FROM
        datalake_ebdb_raw_prod.imovel i
    LEFT JOIN
        datalake_ebdb_raw_prod.listingbusinesscontext lbc
            ON i.id=lbc.imovelid
    INNER JOIN
        dim_partner_agent pa
            ON pa.id_user=i.usuarioquecadastrou_id
    LEFT JOIN
        dim_partner dp
            ON dp.id_partner=pa.id_partner
    LEFT JOIN
        house_change hc
            ON hc.id=i.id
    LEFT JOIN
        sale.dim_listing dl
            ON dl.sk_house=i.id
    LEFT JOIN
        sale.fact_listing_flows lf
            ON LEFT(lf.sk_house_listing,9) = i.id
    WHERE
        businesscontext = 'SALE'
        AND dp.type = 'AUTONOMOUS_AGENT'
        AND i.externalid IS NOT NULL
        AND hc.id IS NULL
    ORDER BY 2
))

SELECT 
    * 
FROM 
    quintoandar_consultant_listings
ORDER BY
    sk_house_listing
