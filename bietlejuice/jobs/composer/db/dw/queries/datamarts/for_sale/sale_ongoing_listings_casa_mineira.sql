WITH old_houses_base AS (   
    WITH aux AS ( 
        WITH revisions AS (
            SELECT
                r.id_revisionable AS id_house,
                house_status.house_status_name AS status,
                RANK() OVER (PARTITION BY r.id_revisionable ORDER BY r.ts_created DESC) AS rw,
                r.ts_created AS dt_revision_created
            FROM 
                datalake_casa_mineira_crm_clean_prod.revisions AS r
                INNER JOIN 
                    datalake_casa_mineira_crm_clean_prod.house_status AS house_status 
                    ON house_status.id = r.new_value
            WHERE 
                r.revision_key = 'status_id'
        )
        SELECT 
            *
        FROM revisions 
        WHERE 
            status = 'Publicado' 
            AND rw = 1
    )
    
    SELECT 
        aux.*
    FROM aux
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.house AS h 
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
        datalake_casa_mineira_crm_clean_prod.house AS h
    WHERE
        h.id_status = 3 
        AND h.id_house_quintoandar IS NULL
), 

final_old_houses_base AS (
    WITH aux_old_houses AS (
        SELECT 
            *
        FROM house_info AS hi
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
        aux_old_houses hb
), 

daily_other_status_listings AS (
    SELECT 
        r.id_revisionable AS id_house,
        hs_new_value.house_status_name AS status,
        r.ts_created AS dt_revision_created
    FROM 
        datalake_casa_mineira_crm_clean_prod.revisions AS r
    INNER JOIN 
        datalake_casa_mineira_crm_clean_prod.house_status AS hs_new_value 
            ON hs_new_value.id = r.new_value
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.house AS h 
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
        nu.id AS sk_region,
        nu.neighborhood_name AS region,
        ctu.city_name,
        uf_name AS city_group
    FROM 
        range_date AS rg
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.house AS h 
            ON  h.id = rg.id_house
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.neighborhood AS nu
            ON nu.id = h.id_neighborhood
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.city AS ctu
            ON ctu.id = nu.id_city
    LEFT JOIN 
        datalake_casa_mineira_crm_clean_prod.uf AS uf
            ON uf.id = ctu.id_uf
    INNER JOIN 
        dim_date AS dd 
            ON  (dd.date BETWEEN dt_start_status_date::DATE
                AND COALESCE(rg.dt_end_status_date::DATE, current_date -1))
    WHERE
        status = 'Publicado'
        ORDER BY 
            1, 2
)

SELECT 
    sk_region,
    region,
    city_name,
    city_group,
    date,
    weekday_name,
    week_start,
    COUNT(DISTINCT id_house) AS ongoing_listings
FROM 
    all_houses_listings AS al 
GROUP BY
    sk_region,
    region,
    city_name,
    city_group,
    date, 
    weekday_name,
    week_start