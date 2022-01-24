WITH loft_listings_raw AS (
    SELECT
        CONCAT(id, 'Loft') AS id_house,
        id AS id_house_platform,
        CONCAT(id, 'Loft', CAST(ROW_NUMBER() OVER (PARTITION BY CONCAT(id, 'Loft') ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS VARCHAR)) AS id_status,
        CAST(address.neighborhood AS VARCHAR) AS neighborhood_loft,
        CAST(geolocation.latitude AS VARCHAR) AS lat,
        CAST(geolocation.longitude AS VARCHAR) AS lng,
        CAST(SUBSTR(CAST(date_info.created_at AS VARCHAR), 1, 10) AS DATE) AS ts_created,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) = 1 THEN TRUE 
            ELSE FALSE
        END AS is_last_status,
        CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) AS ts_updated,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS ts_first_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_publication,
        FIRST_VALUE(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY 1 ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE) DESC) AS ts_last_extraction,
        LAG(CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) OVER (PARTITION BY id ORDER BY CAST(CONCAT(CAST(year AS VARCHAR), '-', CAST(month AS VARCHAR), '-', CAST(day AS VARCHAR)) AS DATE)) AS ts_last_update 
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
            CASE
                WHEN ll.is_last_status = TRUE 
                    AND ll.ts_last_publication = ll.ts_last_extraction THEN 'Publicado'
                WHEN ll.is_last_status = FALSE THEN 'Publicado'
                ELSE 'Despublicado'
            END AS status,
            ll.is_last_status,
            ll.ts_created,
            ll.ts_first_publication,
            ll.ts_last_publication,
            ll.ts_updated,
            ll.ts_last_extraction,
            ll.ts_last_update
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
            status,
            is_last_status,
            ts_created,
            ts_first_publication,
            ts_last_publication,
            ts_updated,
            ts_last_extraction,
            ts_last_update
        FROM
            loft_listings_w_correct_region
        WHERE
            id_status IN (SELECT id_status FROM ids_duplicados)
            AND neighborhood = neighborhood_loft
    )
    SELECT
        id_house,
        id_house_platform,
        id_status, 
        id_neighborhood,
        neighborhood,
        status,
        is_last_status,
        ts_created,
        ts_first_publication,
        ts_last_publication,
        ts_updated,
        ts_last_extraction,
        ts_last_update
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
        id_status,
        id_neighborhood,
        neighborhood,
        status,
        is_last_status,
        ts_created,
        ts_first_publication,
        ts_last_publication,
        ts_updated,
        ts_last_extraction,
        ts_last_update
    FROM
        correct_duplicated_values
    ),
base AS (
    SELECT
        id_house,
        id_house_platform,
        id_neighborhood,
        neighborhood,
        status AS status_history,
        MAX(is_last_status) AS is_last_status,
        ts_created AS ts_created_listing,
        MIN(ts_updated) AS ts_status_started,
        MAX(ts_last_update) AS ts_last_update,
        MAX(ts_last_extraction) AS ts_load
    FROM
        loft_listings_clean
    GROUP BY 1, 2, 3, 4, 5, 7
), 
aux AS ( 
    SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    status_history,
    is_last_status,
    ts_created_listing,
    ts_status_started,
    LEAD(ts_status_started) OVER (PARTITION BY id_house ORDER BY ts_status_started) AS ts_status_ended,
    ts_last_update, 
    ts_load
FROM
    base
)
SELECT
    id_house,
    id_house_platform,
    id_neighborhood,
    neighborhood,
    status_history,
    COALESCE(
        CASE
            WHEN status_history = 'Publicado' THEN DATE_DIFF('week', ts_created_listing, COALESCE(ts_status_ended, CURRENT_DATE))
            WHEN status_history = 'Despublicado' THEN DATE_DIFF('week', ts_created_listing, LAG(ts_status_started) OVER (PARTITION BY id_house ORDER BY ts_status_started))
        END
    , 1) AS weeks_published,
    CASE
        WHEN status_history = 'Despublicado' THEN DATE_DIFF('week', ts_status_started, NOW())
    END AS weeks_unpublished,
    is_last_status,
    CASE 
        WHEN status_history = 'Publicado' AND DATE_DIFF('day', ts_last_update, ts_load) > 7 AND is_last_status = TRUE THEN TRUE 
        ELSE FALSE 
    END AS is_republished, 
    ts_status_started,
    ts_status_ended,
    ts_last_update, 
    ts_load
FROM
    aux

