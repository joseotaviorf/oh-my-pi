WITH first_change_sale AS (
    SELECT
        ia.id_house,
        DATE(MIN(FROM_UNIXTIME(u.ts_revision/ 1000))) AS dt_sale
    FROM
        datalake_ebdb_clean_prod.house_aud ia
    LEFT JOIN 
        datalake_ebdb_clean_prod.user_revision_entity u
            ON u.id=ia.rev
    WHERE 
        is_for_sale=TRUE
    GROUP BY 1
),

first_change_rent AS (
    SELECT
        ia.id_house,
        DATE(MIN(FROM_UNIXTIME(u.ts_revision/ 1000))) AS dt_rent
    FROM
        datalake_ebdb_clean_prod.house_aud ia
    LEFT JOIN 
        datalake_ebdb_clean_prod.user_revision_entity u
            ON u.id=ia.rev
    WHERE 
        is_for_rent=TRUE
    GROUP BY 1
),

base_tempo_rent AS (
    SELECT dhl.sk_house_listing,
        ts_status_start,
        ts_status_end,
        ts_publication,
        CASE 
            WHEN ts_status_start<=DATEADD('day',30,ts_publication) THEN DATEDIFF('day', ts_status_start, 
                CASE 
                    WHEN ts_status_end<= DATEADD('day',30,ts_publication) THEN 
                        CASE 
                            WHEN sk_status_end_date=-1 THEN GETDATE() 
                            ELSE ts_status_end 
                        END 
                    ELSE DATEADD('day',30,ts_publication) 
                END ) 
            ELSE 0 
        END AS tempo
    FROM fact_house_listing_status ls
    LEFT JOIN dim_house_listing dhl
        ON dhl.sk_house_listing=ls.sk_house_listing
    WHERE status_history='publicado' or status_history='alugado'
), 

base_tempo_publicado_rent AS (
    SELECT 
        sk_house_listing,
        SUM(tempo) AS tempo_publicado_for_rent
    FROM base_tempo_rent
    GROUP BY 1
), 

base_tempo_sale AS (
    SELECT ls.sk_sale_listing,
        ts_status_started,
        ts_status_ended,
        dd.date AS first_publication,
        CASE 
            WHEN ts_status_started<=DATEADD('day',30,dd.date) THEN DATEDIFF('day', ts_status_started, 
                CASE 
                    WHEN ts_status_ended<= DATEADD('day',30,dd.date) THEN 
                        CASE 
                            WHEN sk_status_end_date=-1 THEN GETDATE() 
                            ELSE ts_status_ended 
                        END 
                    ELSE DATEADD('day',30,dd.date) 
                END ) 
            ELSE 0 
        END AS tempo 
    FROM sale.fact_listing_status ls
    LEFT JOIN dim_date dd
        ON dd.sk_date=sk_first_publication_date
    WHERE status_history in ('PUBLISHED','CCV_SIGNED','SALE_COMPLETED')
), 

base_tempo_publicado_sale AS (
    SELECT 
        sk_sale_listing,
        SUM(tempo) AS tempo_publicado_for_sale
    FROM base_tempo_sale
    GROUP BY 1
),
supply_sale AS (
    SELECT 
        lf.sk_house_listing, 
        lf.sk_lead_date, 
        lf.sk_first_listing_date,
        lf.mkt_origin
    FROM 
        sale.fact_listing_flows lf
    GROUP BY 1,2,3,4

),
quintoandar_consultant_listings_sale AS (

    SELECT
        dl.sk_sale_listing,
        CAST(JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS BIGINT) AS id_house,
        CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT) AS sk_quintoandar_consultant,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND  program.name='CIQ_FULL' AS is_ciq_origin,
        CASE
            WHEN program.name='CIQ_MANAGER' THEN TRUE
            ELSE FALSE
        END AS is_account_manager,
        program.name AS type_big_agent,
        lbc.business_context AS businesscontext,
        NULL as businesscontext_detail,
        Agency.dt_since AS dt_ciq_started,
        dp.id_partner
    FROM
        datalake_big_agent_prod.House
    LEFT JOIN
        datalake_big_agent_prod.Agency
            ON Agency.id_house=House.id
    LEFT JOIN 
        datalake_big_agent_prod.enrollment
            ON enrollment.id=Agency.id_enrollment
    LEFT JOIN
        datalake_big_agent_prod.Agent
            ON agent.id=enrollment.id_agent
    LEFT JOIN
        datalake_big_agent_prod.program
            ON program.id=enrollment.id_program
    LEFT JOIN
        sale.dim_listing dl
            ON dl.sk_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN
        supply_sale lf
            ON dl.sk_house = lf.sk_house_listing/1000
            AND (lf.sk_lead_date>=20210601 or lf.sk_first_listing_date>=20210601)
    LEFT JOIN 
        dim_partner_agent dpa
            ON dpa.id_user=CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT)
    LEFT JOIN 
        dim_partner dp
            ON dp.id_partner=dpa.id_partner
    INNER JOIN
        datalake_ebdb_clean_prod.listing_business_context lbc
            ON lbc.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
            AND lbc.business_context='SALE'
    WHERE (lf.sk_lead_date>=20210601 OR lf.sk_first_listing_date>=20210601)
    ),
    
check_ciq_full AS (
    SELECT
        JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS id_house_external
    FROM
        datalake_big_agent_prod.House
    INNER JOIN
        datalake_big_agent_prod.Agency
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
        datalake_big_agent_prod.Agency
    GROUP BY 1
),

supply_rent AS (

    SELECT
        mkt_origin,
        sk_house_listing
    FROM 
        fact_house_listing_flows
    GROUP BY 
        1,2

),

quintoandar_consultant_listings_rent AS (
    SELECT
        dhl.sk_house_listing,
        CAST(JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId') AS BIGINT) AS id_house,
        CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT) AS sk_quintoandar_consultant,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND  program.name='CIQ_FULL' AS is_ciq_origin,
        CASE
            WHEN program.name='CIQ_MANAGER' THEN TRUE
            ELSE FALSE
        END AS is_account_manager,
        CASE
            WHEN ccf.id_house_external IS NOT NULL THEN 'CIQ_FULL'
            ELSE program.name
        END AS type_big_agent,
        lbc.business_context AS businesscontext,
        NULL as businesscontext_detail,
        Agency.dt_since AS dt_ciq_started,
        dp.id_partner
    FROM
        datalake_big_agent_prod.House
    LEFT JOIN
        last_enrollment le
            ON le.id_house=House.id
    LEFT JOIN
        datalake_big_agent_prod.Agency
            ON Agency.id_house=le.id_house
            AND Agency.id_enrollment=le.id_enrollment
    LEFT JOIN 
        datalake_big_agent_prod.enrollment
            ON enrollment.id=le.id_enrollment
    LEFT JOIN
        datalake_big_agent_prod.Agent
            ON agent.id=enrollment.id_agent
    LEFT JOIN
        datalake_big_agent_prod.program
            ON program.id=enrollment.id_program
    LEFT JOIN
        dim_house_listing dhl
            ON dhl.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN
        supply_rent lf
            ON dhl.id_house = lf.sk_house_listing/1000
    LEFT JOIN
        check_ciq_full ccf
            ON ccf.id_house_external=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
    LEFT JOIN 
        dim_partner_agent dpa
            ON dpa.id_user=CAST(JSON_EXTRACT_PATH_TEXT(Agent.details, 'userExternalId') AS BIGINT)
    LEFT JOIN 
        dim_partner dp
            ON dp.id_partner=dpa.id_partner
    INNER JOIN
        datalake_ebdb_clean_prod.listing_business_context lbc
            ON lbc.id_house=JSON_EXTRACT_PATH_TEXT(House.details, 'houseExternalId')
            AND lbc.business_context='RENT'
    ),

quintoandar_consultant_listings_uniao AS (
    SELECT * FROM quintoandar_consultant_listings_rent
    UNION ALL
    SELECT * FROM quintoandar_consultant_listings_sale
),

quintoandar_consultant_listings AS (
    SELECT
        qclu.sk_house_listing,
        qclu.id_house,
        qclu.sk_quintoandar_consultant,
        qclu.mkt_origin_ciq,
        qclu.is_ciq_origin,
        qclu.is_account_manager,
        qclu.type_big_agent,
        qclu.businesscontext,
        CASE 
            WHEN btpr.tempo_publicado_for_rent>=15 AND btps.tempo_publicado_for_sale>=15 THEN 'hibrido'
            WHEN btpr.tempo_publicado_for_rent>=15 AND (btps.tempo_publicado_for_sale<15 OR btps.tempo_publicado_for_sale IS NULL) THEN 'rent only'
            WHEN (btpr.tempo_publicado_for_rent<15 OR btpr.tempo_publicado_for_rent IS NULL) AND btps.tempo_publicado_for_sale>=15 THEN 'sale only'
            WHEN btpr.tempo_publicado_for_rent<15 AND btps.tempo_publicado_for_sale<15 THEN 'hibrido - menos de 15 dias publicado'
            WHEN btpr.tempo_publicado_for_rent IS NULL AND btps.tempo_publicado_for_sale IS NULL THEN 'aguardando publicacao'
            WHEN btpr.tempo_publicado_for_rent<15 AND btps.tempo_publicado_for_sale IS NULL THEN 'rent only - menos que 15 dias'
            WHEN btpr.tempo_publicado_for_rent IS NULL AND btps.tempo_publicado_for_sale<15 THEN 'sale only - menos que 15 dias'
            ELSE 'check'
        END AS businesscontext_detail,
        qclu.dt_ciq_started,
        qclu.id_partner,
        lcs.dt_sale,
        lcr.dt_rent
    FROM quintoandar_consultant_listings_uniao qclu
    LEFT JOIN 
        first_change_sale lcs
            ON lcs.id_house=qclu.id_house
    LEFT JOIN 
        first_change_rent lcr
            ON lcr.id_house=qclu.id_house
    LEFT JOIN 
        base_tempo_publicado_rent btpr
            ON btpr.sk_house_listing=qclu.sk_house_listing
    LEFT JOIN 
        base_tempo_publicado_sale btps
            ON btps.sk_sale_listing=qclu.sk_house_listing

)

SELECT * FROM quintoandar_consultant_listings
