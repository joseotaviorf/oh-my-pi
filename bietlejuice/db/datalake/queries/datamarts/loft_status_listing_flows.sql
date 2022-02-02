WITH loft_listings_raw AS (
    SELECT
        CONCAT(id, 'Loft') AS id_house,
        id AS id_house_platform,
        CONCAT(id, 'Loft', CAST(ROW_NUMBER() OVER (PARTITION BY CONCAT(id, 'Loft') ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS VARCHAR)) AS id_status,
        CAST(address.neighborhood AS VARCHAR) AS neighborhood_loft,
        CAST(geolocation.latitude AS VARCHAR) AS lat,
        CAST(geolocation.longitude AS VARCHAR) AS lng,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) = 1 THEN TRUE 
            ELSE FALSE
        END AS is_last_status,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) = 1 THEN TRUE 
            ELSE FALSE
        END AS is_first_status,
        CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) AS ts_updated,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS ts_first_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY 1 ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_extraction
    FROM
        datalake_crawlers_listings_clean_prod.loft
),
regions AS (
    SELECT
        r.id AS id_neighborhood,
        r.name AS neighborhood,
        ST_POLYGON(pr.polygon) AS geometry
    FROM
        datalake_ebdb_clean_prod.polygon_region AS pr
    JOIN
        datalake_ebdb_clean_prod.map_region AS r
            ON r.id = pr.id_region
    WHERE
        r.level = 'SubRegiao'
),
loft_listings_clean AS (
    WITH loft_listings_w_correct_region AS (
        SELECT
            ll.id_house,
            ll.id_house_platform,
            ll.id_status,
            COALESCE(r.id_neighborhood, -1) AS id_neighborhood,
            IF(r.neighborhood IS NULL, ll.neighborhood_loft, r.neighborhood) AS neighborhood,
            ll.neighborhood_loft,
            ll.is_last_status,
            LL.is_first_status,
            ll.ts_first_publication,
            ll.ts_updated,
            ll.ts_last_extraction
        FROM
            loft_listings_raw AS ll
        LEFT JOIN
            regions AS r
                ON ST_WITHIN(ST_POINT(CAST(ll.lng AS DOUBLE), CAST(ll.lat AS DOUBLE)), r.geometry)
    ),
    ids_duplicados AS (
        SELECT
            id_status
        FROM
            loft_listings_w_correct_region
        GROUP BY 1
        HAVING
            COUNT(*) = 2
    ),
    correct_duplicated_values AS (
        SELECT
            id_house,
            id_house_platform,
            id_status,
            id_neighborhood,
            neighborhood,
            neighborhood_loft,
            is_last_status,
            is_first_status,
            ts_first_publication,
            ts_updated,
            ts_last_extraction
        FROM
            loft_listings_w_correct_region
        WHERE
            id_status IN (SELECT id_status FROM ids_duplicados)
            AND neighborhood = neighborhood_loft
    )
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        is_last_status,
        is_first_status,
        ts_first_publication,
        ts_updated,
        ts_last_extraction
    FROM
        loft_listings_w_correct_region
    WHERE
        id_status NOT IN (SELECT id_status FROM ids_duplicados)
    --------------
    UNION
    --------------
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        is_last_status,
        is_first_status,
        ts_first_publication,
        ts_updated,
        ts_last_extraction
    FROM
        correct_duplicated_values
    ),
    dim_date_aux AS (
        SELECT  
            week_start
        FROM 
            datalake_raw.dim_date 
        WHERE 
            CAST(date AS DATE) BETWEEN CAST('2021-06-01' AS DATE) AND (SELECT ts_last_extraction FROM loft_listings_clean LIMIT 1)
        GROUP BY 
            1
    ),
    df_cross_join_aux AS (
        SELECT 
            id_house, 
            id_house_platform, 
            id_neighborhood, 
            neighborhood, 
            ts_first_publication 
        FROM 
            loft_listings_clean 
        GROUP BY 
            1, 2, 3, 4, 5
    ),
    timeline AS (
        SELECT  
            d.week_start,
            l.id_house,
            l.id_house_platform,
            l.id_neighborhood,
            l.neighborhood,
            CASE 
                WHEN CAST(d.week_start AS DATE) >= l.ts_first_publication THEN 1 
                ELSE NULL 
            END AS check_date,
            l.ts_first_publication
        FROM 
            dim_date_aux AS d
        CROSS JOIN 
            df_cross_join_aux AS l
    ),
    df_status_change_aux AS (
        SELECT 
            CAST(t.week_start AS DATE) AS week_start,
            t.id_house_platform,
            t.check_date,
            t.id_house, 
            t.id_neighborhood,
            t.neighborhood,
            CASE 
                WHEN (l.is_first_status IS NULL AND l.is_last_status IS NULL) 
                    AND (LEAD(l.ts_updated) OVER (PARTITION BY t.id_house_platform ORDER BY t.week_start) IS NOT NULL)  
                    AND (lAG(l.ts_updated) OVER (PARTITION BY t.id_house_platform ORDER BY t.week_start) IS NOT NULL) THEN 1
                WHEN (l.is_first_status IS NOT NULL AND l.is_last_status IS NOT NULL) 
                     AND (LAG(l.ts_updated) OVER (PARTITION BY t.id_house_platform ORDER BY t.week_start) IS NULL) THEN 1
                WHEN (l.is_first_status IS NULL AND l.is_last_status IS NULL) 
                    AND (LAG(l.ts_updated) OVER (PARTITION BY t.id_house_platform ORDER BY t.week_start) IS NOT NULL) THEN 1
                ELSE 0 
            END AS status_change_aux,
            l.is_last_status,
            l.is_first_status,
            l.ts_first_publication,
            l.ts_updated,
            l.ts_last_extraction
        FROM 
            timeline AS t 
        LEFT JOIN 
            loft_listings_clean AS l
                ON CAST(t.week_start AS DATE) = l.ts_updated 
                AND t.id_house_platform = l.id_house_platform
        WHERE 
            t.check_date = 1
    ),
    df_status_change AS (
        SELECT
            week_start,
            id_house_platform,
            check_date,
            id_house, 
            id_neighborhood,
            neighborhood,
            CASE 
                WHEN ts_updated IS NOT NULL THEN 'Publicado'
                ELSE 'Despublicado'
            END AS status_history,
            SUM(status_change_aux) OVER (PARTITION BY id_house_platform ORDER BY week_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS status_change,
            status_change_aux,
            is_last_status,
            is_first_status,
            ts_first_publication,
            ts_updated,
            ts_last_extraction
        FROM 
            df_status_change_aux
    ),
    df_grouping AS (
        SELECT 
            id_house,
            id_house_platform,
            id_neighborhood,
            neighborhood,
            status_history,
            status_change,
            MIN(week_start) AS ts_started_date,
            MAX(week_start) AS ts_ended_date
        FROM 
            df_status_change 
        GROUP BY 
            1, 2, 3, 4, 5, 6
    )
SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    status_history,
    FIRST_VALUE(ts_started_date) OVER (PARTITION BY id_house ORDER BY ts_started_date DESC) = ts_started_date AS is_last_status,
    CASE 
        WHEN status_history = 'Publicado' THEN IF(DATE_DIFF('week', ts_started_date, ts_ended_date) = 0, 1, DATE_DIFF('week', ts_started_date, ts_ended_date))
        ELSE NULL 
    END AS weeks_published,
    CASE 
        WHEN status_history = 'Despublicado' THEN IF(DATE_DIFF('week', ts_started_date, ts_ended_date) = 0, 1, DATE_DIFF('week', ts_started_date, ts_ended_date))
        ELSE NULL 
    END AS weeks_unpublished,
    ts_started_date,
    CASE 
        WHEN ts_ended_date = FIRST_VALUE(ts_ended_date) OVER (PARTITION BY 1 ORDER BY ts_ended_date DESC) THEN NULL 
        ELSE ts_ended_date
    END AS ts_ended_date, 
    FIRST_VALUE(ts_ended_date) OVER (PARTITION BY 1 ORDER BY ts_ended_date DESC) AS ts_load 
FROM 
    df_grouping 

