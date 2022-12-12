WITH first_change_sale AS (
    SELECT
        ia.id_house,
        DATE(MIN(FROM_UNIXTIME(u.ts_revision/ 1000))) AS dt_sale
    FROM
        datalake_ebdb_clean.house_aud AS ia
    LEFT JOIN 
        datalake_ebdb_clean.user_revision_entity AS u
            ON u.id = ia.rev
    WHERE 
        is_for_sale = TRUE
    GROUP BY 1
),

first_change_rent AS (
    SELECT
        ia.id_house,
        DATE(MIN(FROM_UNIXTIME(u.ts_revision/ 1000))) AS dt_rent
    FROM
        datalake_ebdb_clean.house_aud AS ia
    LEFT JOIN 
        datalake_ebdb_clean.user_revision_entity AS u
            ON u.id = ia.rev
    WHERE 
        is_for_rent = TRUE
    GROUP BY 1
),

base_tempo_rent AS (
    SELECT 
        dhl.sk_house_listing,
        ts_status_start,
        ts_status_end,
        ts_publication,
        CASE 
            WHEN ts_status_start <= DATE_ADD(ts_publication,30) THEN DATEDIFF(ts_status_start, 
                CASE 
                    WHEN ts_status_end <= DATE_ADD(ts_publication,30) THEN 
                        CASE 
                            WHEN sk_status_end_date = -1 THEN CURRENT_TIMESTAMP() 
                            ELSE ts_status_end 
                        END 
                    ELSE DATE_ADD(ts_publication,30) 
                END ) 
            ELSE 0 
        END AS tempo
    FROM 
        dw_public.fact_house_listing_status AS ls
    LEFT JOIN 
        dw_public.dim_house_listing AS dhl
            ON dhl.sk_house_listing = ls.sk_house_listing
    WHERE 
        status_history = 'publicado' 
        OR status_history = 'alugado'
), 

base_tempo_publicado_rent AS (
    SELECT 
        sk_house_listing,
        SUM(tempo) AS tempo_publicado_for_rent
    FROM 
        base_tempo_rent
    GROUP BY 1
), 

base_tempo_sale AS (
    SELECT 
        ls.sk_sale_listing,
        ts_status_started,
        ts_status_ended,
        dd.date AS first_publication,
        CASE 
            WHEN ts_status_started <= DATE_ADD(dd.date,30) THEN DATEDIFF(ts_status_started, 
                CASE 
                    WHEN ts_status_ended <= DATE_ADD(dd.date,30) THEN 
                        CASE 
                            WHEN sk_status_end_date = -1 THEN CURRENT_TIMESTAMP() 
                            ELSE ts_status_ended 
                        END 
                    ELSE DATE_ADD(dd.date,30) 
                END ) 
            ELSE 0 
        END AS tempo 
    FROM 
        dw_sale.fact_listing_status AS ls
    LEFT JOIN 
        dw_public.dim_date AS dd
            ON dd.sk_date = sk_first_publication_date
    WHERE 
        status_history IN ('PUBLISHED','CCV_SIGNED','SALE_COMPLETED')
), 

base_tempo_publicado_sale AS (
    SELECT 
        sk_sale_listing,
        SUM(tempo) AS tempo_publicado_for_sale
    FROM 
        base_tempo_sale
    GROUP BY 1
),
supply_sale AS (
    SELECT 
        lf.sk_house_listing, 
        lf.sk_lead_date, 
        lf.sk_first_listing_date,
        lf.mkt_origin
    FROM 
        dw_sale.fact_listing_flows AS lf
    GROUP BY 1,2,3,4

),

-- Checks if last Listing update has been deleted from program
agency_last_update AS (
    SELECT 
        id_house,
        MAX(ts_updated) AS aud_agency_dt_updated
    FROM
        datalake_big_agent_clean.agency_aud 
    GROUP BY id_house
    ),
    
agency_last_update_deleted AS (
    SELECT
        aud.id_house AS deleted_id, -- ID_HOUSE when last update has been deleted
        aud.ts_deleted
    FROM
        datalake_big_agent_clean.agency_aud  AS aud
    INNER JOIN
        agency_last_update AS du 
            ON du.id_house = aud.id_house
                AND du.aud_agency_dt_updated = aud.ts_updated
    WHERE
        aud.mod_ts_deleted
),
-- For removal of undue CIQ_Manager listings: gets IDs with status changes or Contract Signed after CIQ_Manager discontinuation
has_status_changed AS (
    SELECT
        sk_house_listing,
        max(ts_status_start) as last_status_change
    FROM
        dw_public.fact_house_listing_status
    WHERE
        ts_status_start > cast('2022-05-20' as timestamp)
    GROUP BY 1
),

sale_status_change AS (
    SELECT
        sk_sale_listing,
        max(ts_status_started) as last_status_change
    FROM
        dw_sale.fact_listing_status
    WHERE
        ts_status_started > cast('2022-05-20' as timestamp)
    GROUP BY 1
),
has_signed_contract AS (
    SELECT
        sk_house_listing
    FROM
        dw_public.fact_listing_rent_flows
    WHERE
        sk_contract_signed_date > 20220520
    GROUP BY 1
 ),


quintoandar_consultant_listings_sale_big_agent_house AS (
    SELECT
        JSON_TUPLE(House.details,'houseExternalId') AS id_house,
        CASE
            WHEN program.name = 'CIQ_MANAGER' THEN TRUE
            ELSE FALSE
        END AS is_account_manager,
        program.name AS type_big_agent,
        Agency.dt_since AS dt_ciq_started,
        Agent.details,
        House.id as datalake_id
    FROM
        datalake_big_agent.House
    LEFT JOIN
        datalake_big_agent.Agency
            ON Agency.id_house = House.id
    LEFT JOIN 
        datalake_big_agent.enrollment
            ON enrollment.id = Agency.id_enrollment
    LEFT JOIN
        datalake_big_agent.Agent
            ON agent.id = enrollment.id_agent
    LEFT JOIN
        datalake_big_agent.program
            ON program.id = enrollment.id_program
),

quintoandar_consultant_listings_sale_big_agent_agent AS (
    SELECT
        CAST(id_house AS BIGINT) AS id_house,
        is_account_manager,
        type_big_agent,
        dt_ciq_started,
        JSON_TUPLE(details,'userExternalId') AS sk_quintoandar_consultant,
        datalake_id
    FROM 
        quintoandar_consultant_listings_sale_big_agent_house
),

quintoandar_consultant_listings_sale_raw AS (
   SELECT
        dl.sk_sale_listing,
        a.id_house,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND type_big_agent = 'CIQ_FULL' AS is_ciq_origin,
        is_account_manager,
        CASE
            WHEN type_big_agent = 'CIQ_MANAGER'
                AND lcs.dt_sale > dt_ciq_started THEN 'CIQ_FULL'
            ELSE type_big_agent
        END as type_big_agent,
        dt_ciq_started,
        CAST(sk_quintoandar_consultant AS BIGINT) AS sk_quintoandar_consultant,
        lbc.business_context AS businesscontext,
        NULL AS businesscontext_detail,
        dp.id_partner,
        dl.status AS house_status,
        ssc.sk_sale_listing AS status_change_id,
        last_status_change,
        0 AS contract_signed_id,
        mud.ts_deleted
    FROM
       quintoandar_consultant_listings_sale_big_agent_agent AS a
    LEFT JOIN
        dw_sale.dim_listing AS dl
            ON dl.sk_house = a.id_house
    LEFT JOIN
        supply_sale AS lf
            ON dl.sk_house = lf.sk_house_listing/1000
            AND (lf.sk_lead_date >= 20210601 
                OR lf.sk_first_listing_date >= 20210601)
    LEFT JOIN 
        dw_public.dim_partner_agent AS dpa
            ON dpa.id_user = a.sk_quintoandar_consultant
    LEFT JOIN 
        dw_public.dim_partner AS dp
            ON dp.id_partner = dpa.id_partner
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = a.id_house
            AND lbc.business_context = 'SALE'
    LEFT JOIN
        agency_last_update_deleted as mud
            ON a.datalake_id = mud.deleted_id
    LEFT JOIN
        sale_status_change as ssc
            on dl.sk_sale_listing = ssc.sk_sale_listing
    LEFT JOIN 
        first_change_sale AS lcs
            ON lcs.id_house = a.id_house
    WHERE 
        (lf.sk_lead_date >= 20210601
        OR lf.sk_first_listing_date >= 20210601)
),

quintoandar_consultant_listings_sale AS (
    SELECT *,
        CASE
              WHEN (house_status = 'PUBLISHED' OR status_change_id IS NOT NULL)
                  AND ts_deleted IS NOT NULL 
                  AND type_big_agent NOT IN ('CIQ_FULL','ASP') THEN 1
              ELSE 0
        END AS is_incorrect_attribution
    FROM quintoandar_consultant_listings_sale_raw
),


supply_rent AS (
    SELECT
        mkt_origin,
        sk_house_listing
    FROM 
        dw_public.fact_house_listing_flows
    GROUP BY 
        1,2

),

last_enrollment AS (
    SELECT
        id_house,
        MAX(id_enrollment) AS id_enrollment
    FROM
        datalake_big_agent.Agency
    GROUP BY 1
),

check_ciq_full AS (
    SELECT
        house.id AS id_house
    FROM
        datalake_big_agent.House
    INNER JOIN
        datalake_big_agent.Agency
            ON Agency.id_house = house.id
    GROUP BY
        1
    HAVING
        count(id_house)  > 1
),

quintoandar_consultant_listings_rent_big_agent_house AS (
    SELECT
        json_tuple(House.details,'houseExternalId') AS id_house,
        CASE
            WHEN program.name = 'CIQ_MANAGER' THEN TRUE
            ELSE FALSE
        END AS is_account_manager,
        CASE
            WHEN ccf.id_house IS NOT NULL THEN 'CIQ_FULL'
            ELSE program.name
        END AS type_big_agent,
        Agency.dt_since AS dt_ciq_started,
        Agent.details,
        House.id as datalake_id
    FROM
        datalake_big_agent.House
    LEFT JOIN
        last_enrollment AS le
            ON le.id_house = House.id
    LEFT JOIN
        datalake_big_agent.Agency
            ON Agency.id_house = le.id_house
            AND Agency.id_enrollment = le.id_enrollment
    LEFT JOIN 
        datalake_big_agent.enrollment
            ON enrollment.id = Agency.id_enrollment
    LEFT JOIN
        datalake_big_agent.Agent
            ON agent.id = enrollment.id_agent
    LEFT JOIN
        datalake_big_agent.program
            ON program.id = enrollment.id_program
    LEFT JOIN
        check_ciq_full AS ccf
            ON ccf.id_house = House.id
),

quintoandar_consultant_listings_rent_big_agent_agent AS (

    SELECT
        CAST(id_house AS BIGINT) AS id_house,
        is_account_manager,
        type_big_agent,
        dt_ciq_started,
        JSON_TUPLE(details,'userExternalId') AS sk_quintoandar_consultant,
        datalake_id
    FROM 
        quintoandar_consultant_listings_rent_big_agent_house
),
quintoandar_consultant_listings_rent AS (
   SELECT
        dhl.sk_house_listing,
        a.id_house,
        lf.mkt_origin = 'CIQ' AS mkt_origin_ciq,
        lf.mkt_origin = 'CIQ' AND  type_big_agent = 'CIQ_FULL' AS is_ciq_origin,
        is_account_manager,
        type_big_agent,
        dt_ciq_started,
        CAST(sk_quintoandar_consultant AS BIGINT) AS sk_quintoandar_consultant,
        lbc.business_context AS businesscontext,
        NULL AS businesscontext_detail,
        dp.id_partner,
        dhl.status AS house_status,
        hsc.sk_house_listing AS status_change_id,
        last_status_change,
        hcs.sk_house_listing AS contract_signed_id,
        mud.ts_deleted,
        CASE
            WHEN (dhl.status = 'publicado' OR hsc.sk_house_listing IS NOT NULL OR hcs.sk_house_listing IS NOT NULL)
    			AND mud.deleted_id IS NOT NULL
                AND type_big_agent NOT IN ('CIQ_FULL','ASP')  THEN 1
            ELSE 0
        END AS is_incorrect_attribution
    FROM
       quintoandar_consultant_listings_rent_big_agent_agent AS a
    LEFT JOIN
        dw_public.dim_house_listing AS dhl
            ON dhl.id_house = a.id_house
    LEFT JOIN
        supply_rent AS lf
            ON dhl.id_house = lf.sk_house_listing/1000
    LEFT JOIN 
        dw_public.dim_partner_agent AS dpa
            ON dpa.id_user = a.sk_quintoandar_consultant
    LEFT JOIN 
        dw_public.dim_partner AS dp
            ON dp.id_partner = dpa.id_partner
    INNER JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = a.id_house
            AND lbc.business_context = 'RENT'
    LEFT JOIN
        agency_last_update_deleted AS mud
            ON a.datalake_id = mud.deleted_id
    LEFT JOIN
        has_status_changed AS hsc
            ON dhl.sk_house_listing = hsc.sk_house_listing
    LEFT JOIN
        has_signed_contract as hcs
            ON dhl.sk_house_listing = hcs.sk_house_listing

),

quintoandar_consultant_listings_uniao AS (
    SELECT * FROM quintoandar_consultant_listings_rent
    UNION ALL
    SELECT * FROM quintoandar_consultant_listings_sale
),

quintoandar_consultant_published AS (
   SELECT *,
      CASE
          WHEN (house_status = 'publicado' OR house_status = 'PUBLISHED')
              AND type_big_agent = 'CIQ_MANAGER' THEN 1
          ELSE 0
      END AS is_published_ciq_manager
   FROM quintoandar_consultant_listings_uniao
),

-- published CIQ_Manager listings are to be considered Core (outside CIQ Program) since 20/05/2022
-- Some exception listings had no deleted_date from CIQ_Manager program, so aditional filter was needed for Published CIQ_Manager listings to not show in output
quintoandar_consultant_listings_filter AS (
    SELECT *
    FROM quintoandar_consultant_published
    WHERE
        is_incorrect_attribution = 0
        AND is_published_ciq_manager = 0
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
            WHEN btpr.tempo_publicado_for_rent >=15 
              AND btps.tempo_publicado_for_sale >=15 
              AND DATE_TRUNC('MONTH',lcs.dt_sale) = DATE_TRUNC('MONTH',lcr.dt_rent) 
            THEN 'hibrido'
            WHEN btpr.tempo_publicado_for_rent >=15 
              AND btps.tempo_publicado_for_sale >=15 
              AND DATE_TRUNC('MONTH',lcs.dt_sale) > DATE_TRUNC('MONTH',lcr.dt_rent) 
            THEN 'migrado para FS'
            WHEN btpr.tempo_publicado_for_rent >= 15 
              AND btps.tempo_publicado_for_sale >= 15 
              AND DATE_TRUNC('MONTH',lcs.dt_sale) < DATE_TRUNC('MONTH',lcr.dt_rent) 
            THEN 'migrado para FR'
            WHEN btpr.tempo_publicado_for_rent >= 15 
                AND btps.tempo_publicado_for_sale IS NULL 
            THEN 'rent only'
            WHEN btpr.tempo_publicado_for_rent IS NULL 
                AND btps.tempo_publicado_for_sale >= 15 
            THEN 'sale only'
            WHEN btpr.tempo_publicado_for_rent >= 15 
                AND btps.tempo_publicado_for_sale < 15 
            THEN 'rent only - menos que 15 dias em sale'
            WHEN btpr.tempo_publicado_for_rent < 15 
                AND btps.tempo_publicado_for_sale >= 15 
            THEN ' sale only - menos de 15 dias em rent'
            WHEN btpr.tempo_publicado_for_rent < 15 
                AND btps.tempo_publicado_for_sale < 15 
            THEN 'hibrido - menos de 15 dias publicado'
            WHEN btpr.tempo_publicado_for_rent IS NULL 
                AND btps.tempo_publicado_for_sale IS NULL 
            THEN 'aguardando publicacao'
            WHEN btpr.tempo_publicado_for_rent < 15 
                AND btps.tempo_publicado_for_sale IS NULL 
            THEN 'rent only - menos que 15 dias'
            WHEN btpr.tempo_publicado_for_rent IS NULL 
                AND btps.tempo_publicado_for_sale < 15 
            THEN 'sale only - menos que 15 dias'
            ELSE 'check'
        END AS businesscontext_detail,
        qclu.dt_ciq_started,
        qclu.id_partner,
        lcs.dt_sale,
        lcr.dt_rent,
        CAST(ts_deleted AS DATE) AS dt_last_update_deleted
    FROM 
        quintoandar_consultant_listings_filter AS qclu
    LEFT JOIN 
        first_change_sale AS lcs
            ON lcs.id_house = qclu.id_house
    LEFT JOIN 
        first_change_rent AS lcr
            ON lcr.id_house = qclu.id_house
    LEFT JOIN 
        base_tempo_publicado_rent AS btpr
            ON btpr.sk_house_listing = qclu.sk_house_listing
    LEFT JOIN 
        base_tempo_publicado_sale AS btps
            ON btps.sk_sale_listing = qclu.sk_house_listing

)

SELECT * FROM quintoandar_consultant_listings

