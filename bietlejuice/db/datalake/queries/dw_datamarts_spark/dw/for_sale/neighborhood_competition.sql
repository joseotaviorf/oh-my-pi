WITH quintoandar_metrics AS (
    WITH base_ongoing_listings AS (
        SELECT 
            LEFT(f.sk_sale_listing, 9) AS sk_house,
            f.sk_region,
            r.name AS neighborhood, 
            r.city_name AS city,
            f.status_history,
            f.is_last_status,
            ROW_NUMBER() OVER (PARTITION BY f.sk_sale_listing ORDER BY f.ts_status_started) AS order_status,
            TO_DATE(CAST(sk_status_start_date AS STRING), 'yyyyMMdd') AS ts_started_date,
            TO_DATE(CAST(sk_status_end_date AS STRING), 'yyyyMMdd') AS ts_ended_date
        FROM 
            dw_sale.fact_listing_status AS f
        LEFT JOIN 
            dw_public.dim_region AS r
                USING(sk_region)
        ),
        aux_ongoing_listings AS (
            SELECT 
                d.date, 
                d.week_start,
                d.week_end,
                b.sk_house, 
                b.sk_region,
                b.neighborhood,
                b.city,
                b.status_history, 
                b.is_last_status, 
                b.order_status, 
                b.ts_started_date,
                b.ts_ended_date,
                CASE 
                    WHEN b.status_history = 'PUBLISHED' AND d.date = b.ts_started_date THEN TRUE 
                    ELSE FALSE 
                END AS is_publication_flag,
                CASE 
                    WHEN b.status_history = 'PUBLISHED' AND b.order_status = 1 AND d.date = b.ts_started_date 
                    THEN TRUE ELSE FALSE 
                END AS is_first_listing_flag,
                CASE 
                    WHEN b.status_history = 'PUBLISHED' AND b.order_status > 1 AND d.date = b.ts_started_date THEN TRUE 
                    ELSE FALSE 
                END AS is_republication_flag,
                CASE 
                    WHEN b.status_history = 'UNPUBLISHED' AND d.date = b.ts_started_date THEN TRUE 
                    ELSE FALSE 
                END AS is_depublication_flag
            FROM 
                base_ongoing_listings AS b
            JOIN 
                dw_public.dim_date AS d
                    ON d.date BETWEEN b.ts_started_date
                    AND COALESCE(b.ts_ended_date, DATE_ADD(CURRENT_DATE, -1))
        ),
        ongoing_listings AS (
            SELECT 
                week_start,
                sk_region, 
                city, 
                neighborhood,
                NULL AS property_listings,
                NULL AS uniqueness_listings,
                COUNT(
                    DISTINCT 
                        CASE 
                            WHEN status_history = 'PUBLISHED' AND week_end = date THEN sk_house 
                            ELSE NULL 
                        END) AS ongoing_listings,
                NULL AS publications,
                NULL AS depublications,
                NULL AS first_listings,
                NULL AS republications
            FROM 
                aux_ongoing_listings
            GROUP BY 
                1, 2, 3, 4
        ),
        base_publications AS (
            SELECT 
                d.date,
                d.sk_date,
                d.week_start,
                d.week_end, 
                LEFT(ls.sk_sale_listing, 9) AS sk_house,
                ls.sk_region,
                ls.sk_first_publication_date,
                ls.sk_status_start_date, 
                ls.status_history,
                ls.is_last_status,
                r.city_name AS city,
                r.name AS neighborhood
            FROM
                dw_sale.fact_listing_status AS ls
            LEFT JOIN
                dw_public.dim_date AS d 
                    ON d.sk_date = ls.sk_status_start_date
            LEFT JOIN 
                dw_public.dim_region AS r 
                    USING(sk_region)
        ),
        publications_logic AS (
            SELECT
                date,
                week_start, 
                sk_region,
                city,
                neighborhood,
                COUNT(
                    DISTINCT 
                        CASE 
                            WHEN (status_history = 'PUBLISHED') THEN sk_house 
                            ELSE NULL 
                        END) AS publications,
                COUNT(
                    DISTINCT 
                        CASE 
                            WHEN (status_history = 'UNPUBLISHED') THEN sk_house 
                            ELSE NULL 
                        END) AS depublications,
                COUNT(
                    DISTINCT 
                        CASE 
                            WHEN (sk_first_publication_date = sk_status_start_date AND status_history = 'PUBLISHED') THEN sk_house 
                            ELSE NULL 
                        END) AS first_listings,
                COUNT(
                    DISTINCT 
                        CASE 
                            WHEN (sk_first_publication_date != sk_status_start_date AND status_history = 'PUBLISHED') THEN sk_house 
                            ELSE NULL 
                        END) AS republications
            FROM 
                base_publications 
            GROUP BY 
                1, 2, 3, 4, 5
        ),
        publications AS (
            SELECT 
                week_start, 
                sk_region,
                city,
                neighborhood,
                SUM(NULL) AS property_listings,
                SUM(NULL) AS uniqueness_listings,
                SUM(NULL) AS ongoing_listings,
                SUM(publications) AS publications,
                SUM(depublications) AS depublications,
                SUM(first_listings) AS first_listings,
                SUM(republications) AS republications
            FROM 
                publications_logic
            GROUP BY 
                1, 2, 3, 4
        ),
        union_metrics AS (
            SELECT 
                week_start,
                sk_region,
                city,
                neighborhood,
                property_listings,
                uniqueness_listings,
                ongoing_listings,
                publications,
                depublications,
                first_listings,
                republications
            FROM 
                ongoing_listings
            ----------------
            UNION ALL 
            ----------------
            SELECT 
                week_start,
                sk_region,
                city,
                neighborhood,
                property_listings,
                uniqueness_listings,
                ongoing_listings,
                publications,
                depublications,
                first_listings,
                republications
            FROM 
                publications
        ) 
        SELECT 
            week_start,
            'QuintoAndar' AS player, 
            sk_region,
            city,
            neighborhood,
            COALESCE(SUM(property_listings), 0) AS property_listings,
            COALESCE(SUM(uniqueness_listings), 0) AS uniqueness_listings,
            COALESCE(SUM(ongoing_listings), 0) AS ongoing_listings,
            COALESCE(SUM(publications), 0) AS publications,
            COALESCE(SUM(depublications), 0) AS depublications,
            COALESCE(SUM(first_listings), 0) AS first_listings,
            COALESCE(SUM(republications), 0) AS republications
        FROM
            union_metrics
        WHERE 
            week_start >= TO_DATE('20210601', 'yyyyMMdd')
        GROUP BY 
            1, 2, 3, 4, 5
),
casa_mineira_metrics AS (
    WITH old_houses_base AS (
        WITH aux AS (
            WITH revisions AS (
                SELECT
                    r.id_revisionable AS id_house,
                    hs.house_status_name AS status,
                    RANK() OVER (PARTITION BY r.id_revisionable ORDER BY r.ts_created DESC) AS rw,
                    r.ts_created AS dt_revision_created
                FROM 
                    datalake_casa_mineira_crm_clean.revisions AS r
                    INNER JOIN 
                        datalake_casa_mineira_crm_clean.house_status AS hs 
                        ON hs.id = r.new_value
                WHERE 
                    r.revision_key = 'status_id'
            )
            SELECT 
                *
            FROM 
                revisions 
            WHERE 
                status = 'Publicado' 
                AND rw = 1
        )
        SELECT 
            aux.*
        FROM 
            aux
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.house AS h 
                ON h.id = aux.id_house
        WHERE
            h.id_house_quintoandar IS NULL
    ), 
    house_info AS (
        SELECT
            h.id,
            h.id_status,
            h.id_house_quintoandar,
            h.ts_published,
            h.ts_disabled
        FROM 
            datalake_casa_mineira_crm_clean.house AS h
        WHERE
            h.id_status = 3 
            AND h.id_house_quintoandar IS NULL
    ), 
    final_old_houses_base AS (
        WITH aux_old_houses AS (
            SELECT 
                *
            FROM 
                house_info AS hi
            LEFT JOIN 
                old_houses_base l 
                    ON hi.id = l.id_house
            WHERE 
                status IS NULL
        )
        SELECT 
            hb.id AS id_house,
            'Publicado' AS status,
            hb.ts_published AS dt_published
        FROM 
            aux_old_houses AS hb
    ), 
    daily_other_status_listings AS (
        SELECT 
            r.id_revisionable AS id_house,
            hs_new_value.house_status_name AS status,
            r.ts_created AS dt_revision_created
        FROM 
            datalake_casa_mineira_crm_clean.revisions AS r
        INNER JOIN 
            datalake_casa_mineira_crm_clean.house_status AS hs_new_value 
                ON hs_new_value.id = r.new_value
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.house AS h 
                ON h.id = r.id_revisionable 
        WHERE
            r.revision_key = 'status_id' 
            AND h.id_house_quintoandar IS NULL 
    ), 
    all_houses_listings AS (
        WITH aux AS (
            SELECT 
                id_house,
                status,
                dt_revision_created AS dt_start_status_date
            FROM 
                daily_other_status_listings

            UNION

            SELECT 
                id_house,
                status,
                dt_published AS dt_start_status_date
            FROM 
                final_old_houses_base
        ),     
        range_date AS (
            SELECT
                al.id_house,
                al.status,
                al.dt_start_status_date,
                LEAD(al.dt_start_status_date) OVER (PARTITION BY id_house ORDER BY al.dt_start_status_date) AS dt_end_status_date
            FROM 
                aux AS al			
        )
        SELECT  
            rg.id_house,
            rg.status,
            rg.dt_start_status_date,
            rg.dt_end_status_date,
            dd.date,
            dd.weekday_name,
            dd.week_start,
            dd.week_end,
            ctu.id || '000' || nu.id AS sk_region,
            nu.neighborhood_name AS neighborhood,
            ctu.city_name AS city,
            uf_name AS city_group
        FROM 
            range_date AS rg
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.house AS h 
                ON  h.id = rg.id_house
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.neighborhood AS nu
                ON nu.id = h.id_neighborhood
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.city AS ctu
                ON ctu.id = nu.id_city
        LEFT JOIN 
            datalake_casa_mineira_crm_clean.uf AS uf
                ON uf.id = ctu.id_uf
        INNER JOIN 
            dw_public.dim_date AS dd 
                ON (dd.date BETWEEN DATE(dt_start_status_date)
                  AND COALESCE(DATE(rg.dt_end_status_date), current_date -1))
        WHERE
            status = 'Publicado'
            AND dd.date >= TO_DATE('20210601', 'yyyyMMdd')
    )
    SELECT 
        week_start,
        'CasaMineira' AS player,
        sk_region,
        city,
        neighborhood,
        SUM(0) AS property_listings,
        SUM(0) AS uniqueness_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN week_end = date THEN id_house 
                    ELSE NULL 
                END) AS ongoing_listings,
        SUM(0) AS publications,
        SUM(0) AS first_listings,
        SUM(0) AS depublications,
        SUM(0) AS republications
    FROM 
        all_houses_listings AS al 
    GROUP BY
        1, 2, 3, 4, 5
        
),
loft_metrics AS (
    WITH base AS (
        SELECT 
            id_house AS sk_house, 
            id_neighborhood AS sk_region,
            neighborhood,
            status_history,
            is_last_status, 
            ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_started_date) AS order_status,
            DATE(ts_started_date) AS ts_started_date,
            DATE(ts_ended_date) AS ts_ended_date
        FROM 
            dw_datamarts_for_sale.loft_status_listing_flows
    ), 
    ongoing_listings AS (
        SELECT 
            d.week_start,
            b.sk_house, 
            b.sk_region,
            b.neighborhood, 
            b.status_history, 
            b.is_last_status, 
            b.order_status, 
            b.ts_started_date,
            b.ts_ended_date
        FROM 
            base AS b
        JOIN 
            dw_public.dim_date AS d
                ON d.date BETWEEN b.ts_started_date
                AND COALESCE(b.ts_ended_date, DATE_ADD(CURRENT_DATE, -1))
        WHERE 
            d.week_start >= TO_DATE('20210601', 'yyyyMMdd')
        GROUP BY 
            1, 2, 3, 4, 5, 6, 7, 8, 9
    )
    SELECT 
        ol.week_start,
        'Loft' AS player,
        ol.sk_region, 
        h.city, 
        ol.neighborhood,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN ol.status_history = 'Publicado' THEN ol.sk_house 
                    ELSE NULL 
                END) AS ongoing_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND  h.is_platform_property = 'True') THEN ol.sk_house 
                    ELSE NULL 
                END) AS property_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND h.is_exclusive = 'True') THEN ol.sk_house 
                    ELSE NULL 
                END) AS uniqueness_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = week_start) THEN ol.sk_house 
                    ELSE NULL 
                END) AS publications,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status = 1) THEN ol.sk_house 
                    ELSE NULL 
                END) AS first_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status > 1) THEN ol.sk_house 
                    ELSE NULL 
                END) AS republications,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Despublicado' AND ol.ts_started_date = ol.week_start) THEN ol.sk_house 
                    ELSE NULL 
                END) AS depublications
    FROM 
        ongoing_listings AS ol 
    LEFT JOIN 
        dw_datamarts_for_sale.loft_house_listing AS h
            ON ol.sk_house = h.id_house
    GROUP BY 
        1, 2, 3, 4, 5
),
em_casa_metrics AS (
    WITH base AS (
        SELECT 
            id_house AS sk_house, 
            id_neighborhood AS sk_region,
            neighborhood,
            status_history,
            is_last_status, 
            ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY ts_started_date) AS order_status,
            DATE(ts_started_date) AS ts_started_date,
            DATE(ts_ended_date) AS ts_ended_date
        FROM 
            dw_datamarts_for_sale.em_casa_house_listing_flows
    ),
    ongoing_listings AS (
        SELECT 
            d.week_start,
            b.sk_house, 
            b.sk_region,
            b.neighborhood, 
            b.status_history, 
            b.is_last_status, 
            b.order_status, 
            b.ts_started_date,
            b.ts_ended_date
        FROM 
            base AS b
        JOIN 
            dw_public.dim_date AS d
                ON d.date BETWEEN b.ts_started_date
                AND COALESCE(b.ts_ended_date, DATE_ADD(CURRENT_DATE, -1))
        WHERE 
            week_start >= TO_DATE('20210601', 'yyyyMMdd')
        GROUP BY 
            1, 2, 3, 4, 5, 6, 7, 8, 9
    )
    SELECT 
        ol.week_start,
        'EmCasa' AS player,
        ol.sk_region, 
        h.city, 
        ol.neighborhood,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN ol.status_history = 'Publicado' THEN ol.sk_house 
                    ELSE NULL 
                END) AS ongoing_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND  h.is_platform_property = 'True') THEN ol.sk_house 
                    ELSE NULL 
                END) AS property_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND h.is_exclusive = 'True') THEN ol.sk_house 
                    ELSE NULL 
                END) AS uniqueness_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = week_start) THEN ol.sk_house 
                    ELSE NULL 
                END) AS publications,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status = 1) THEN ol.sk_house 
                    ELSE NULL 
                END) AS first_listings,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Publicado' AND ol.ts_started_date = ol.week_start AND ol.order_status > 1) THEN ol.sk_house 
                    ELSE NULL 
                END) AS republications,
        COUNT(
            DISTINCT 
                CASE 
                    WHEN (ol.status_history = 'Despublicado' AND ol.ts_started_date = ol.week_start) THEN ol.sk_house 
                    ELSE NULL 
                END) AS depublications
    FROM 
        ongoing_listings AS ol 
    LEFT JOIN 
        dw_datamarts_for_sale.em_casa_house_listing AS h
            ON ol.sk_house = h.id_house
    GROUP BY 
        1, 2, 3, 4, 5
),
all_metrics AS (
    SELECT 
        week_start,
        player, 
        sk_region,
        city,
        neighborhood,
        property_listings,
        uniqueness_listings,
        ongoing_listings,
        publications,
        depublications,
        first_listings,
        republications 
    FROM 
        quintoandar_metrics
    ---------
    UNION ALL
    ---------
    SELECT 
        week_start,
        player, 
        sk_region,
        city,
        neighborhood,
        property_listings,
        uniqueness_listings,
        ongoing_listings,
        publications,
        depublications,
        first_listings,
        republications
    FROM 
        casa_mineira_metrics
    ---------
    UNION ALL
    ---------
    SELECT 
        week_start,
        player, 
        sk_region,
        city,
        neighborhood,
        property_listings,
        uniqueness_listings,
        ongoing_listings,
        publications,
        depublications,
        first_listings,
        republications
    FROM 
        loft_metrics
    ---------
    UNION ALL
    ---------
    SELECT 
        week_start,
        player, 
        sk_region,
        city,
        neighborhood,
        property_listings,
        uniqueness_listings,
        ongoing_listings,
        publications,
        depublications,
        first_listings,
        republications
    FROM 
        em_casa_metrics
),
enrich_metrics AS (
    SELECT 
        CAST(week_start AS DATE) AS week_start,
        player, 
        sk_region,
        city,
        neighborhood,
        CAST(property_listings AS BIGINT) AS property_listings,
        CAST(uniqueness_listings AS BIGINT) AS uniqueness_listings,
        CAST(ongoing_listings AS BIGINT) AS ongoing_listings,
        CAST(publications AS BIGINT) AS publications,
        CAST(depublications AS BIGINT) AS depublications,
        CAST(first_listings AS BIGINT) AS first_listings,
        CAST(republications AS BIGINT) AS republications
    FROM 
        all_metrics
)
SELECT 
    week_start,
    player, 
    sk_region,
    city,
    neighborhood,
    property_listings,
    uniqueness_listings,
    ongoing_listings,
    publications,
    depublications,
    first_listings,
    republications,
    CURRENT_TIMESTAMP AS ts_load
FROM 
    all_metrics
