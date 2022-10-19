WITH regions_normalization AS (
    WITH regions AS (
        SELECT
            r.id AS id_region,
            r.name,
            ST_GeomFromWKT(p.polygon) AS polygon
        FROM
            datalake_region.region AS r
        LEFT JOIN
            datalake_ebdb_clean.polygon_region AS p
                ON p.id_region = r.id
        WHERE
            r.city_group = 'RMSP'
            AND r.city_name = 'São Paulo'
            AND r.level = 'SubRegiao'
            AND p.polygon IS NOT NULL
    ),
    depara_neighborhoods AS (
        WITH quintoandar_zipcodes AS (
            SELECT
                h.id AS id_house,
                h.id_region,
                h.zipcode,
                h.address,
                h.number
            FROM
                datalake_ebdb_listing.house AS h
            JOIN
                datalake_ebdb_listing.house_listing AS hl
                    ON hl.id_house = h.id
            WHERE
                h.id_region IS NOT NULL
                AND h.zipcode IS NOT NULL
                AND CAST(h.zipcode AS BIGINT) IS NULL
                AND (LENGTH(h.zipcode) - LENGTH(REPLACE(h.zipcode, '-', ''))) = 1
                AND h.zipcode NOT IN ('0', '00000-000', '00000-001')
        ),
        metrics AS (
            WITH metrics_aux AS (
                SELECT
                    zipcode,
                    name,
                    id_region,
                    COUNT(DISTINCT id_house) AS listings_by_zipcode,
                    COUNT(DISTINCT address) AS streets_by_zipcode,
                    COUNT(DISTINCT address||number) AS buildings_by_zipcode
                FROM
                    quintoandar_zipcodes
                LEFT JOIN
                    regions
                        USING(id_region)
                WHERE
                    name IS NOT NULL
                GROUP BY
                    1, 2, 3
            )
            SELECT
                zipcode,
                name,
                id_region,
                listings_by_zipcode,
                streets_by_zipcode,
                buildings_by_zipcode,
                SIZE(COLLECT_SET(name) OVER (PARTITION BY zipcode)) AS neighborhoods_by_zipcode,
                ROW_NUMBER() OVER (PARTITION BY zipcode ORDER BY listings_by_zipcode DESC) AS ranking_by_neighborhood
            FROM
                metrics_aux
        ),
        discard_rules AS (
            SELECT
                zipcode,
                name,
                id_region,
                listings_by_zipcode,
                streets_by_zipcode,
                buildings_by_zipcode,
                neighborhoods_by_zipcode,
                ranking_by_neighborhood,
                CASE
                    WHEN neighborhoods_by_zipcode > 3 THEN 'DISCARD'
                    WHEN neighborhoods_by_zipcode > 1 AND listings_by_zipcode = 1 THEN 'DISCARD'
                    WHEN neighborhoods_by_zipcode > 1 AND ranking_by_neighborhood > 1 THEN 'DISCARD'
                    ELSE NULL
                END AS check
            FROM
                metrics
        )
    SELECT
        id_region,
        name,
        zipcode
    FROM
        discard_rules
    WHERE
        check IS NULL
    ),
    cep_api AS (
        WITH aux_cep_api AS (
            SELECT
                c.zipcode,
                c.address,
                c.neighborhood,
                r.id_region,
                c.lng,
                c.lat,
                CASE
                    WHEN c.neighborhood = r.name THEN r.name
                    ELSE NULL
                END AS neighborhood_quintoandar_match
            FROM
                datalake_gsheets_clean.zipcodes_sp AS c
            LEFT JOIN
                regions AS r
                    ON c.neighborhood = r.name
            GROUP BY
                1, 2, 3, 4, 5, 6, 7
        )
        SELECT
            zipcode,
            address,
            neighborhood,
            id_region,
            IF(lat IS NOT NULL AND lng IS NOT NULL, ST_Point(lng, lat), NULL) AS points,
            neighborhood_quintoandar_match
        FROM
            aux_cep_api
    )
    SELECT
        c.zipcode AS zipcode,
        COALESCE(d.id_region, c.id_region, r.id_region, -1) AS id_region,
        COALESCE(d.name, c.neighborhood_quintoandar_match, r.name, c.neighborhood) AS neighborhood,
        ARRAY_JOIN(TRANSFORM(SPLIT(c.address, ' '), x -> IF(CAST(x AS BIGINT) IS NOT NULL, '', x)), ' ') AS address
    FROM
        cep_api AS c
    LEFT JOIN
        depara_neighborhoods AS d
            ON c.zipcode = d.zipcode
    LEFT JOIN
        regions AS r
            ON c.points IS NOT NULL
            AND ST_Within(c.points, r.polygon) = TRUE
)
SELECT
      zipcode,
      id_region,
      neighborhood,
      address
FROM
      regions_normalization
