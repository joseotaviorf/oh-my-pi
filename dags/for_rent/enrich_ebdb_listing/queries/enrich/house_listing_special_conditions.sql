WITH
special_conditions_prev AS (
-- filter multiple changes in a single day
-- example:
-- ----------------------------------------------------------------------------------------------------------------------------------
-- |     id      |  special_condition_type  |       ts_opted_in      |       ts_opted_out      |    special_condition_status_mod    |
-- ----------------------------------------------------------------------------------------------------------------------------------
-- |    33713    |       Exclusivity	    |   2019-04-24 21:01:08	 |           null          |                1 (opt-in)          | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:01:08	 |    2019-04-24 21:01:10  |                1 (opt-out)         | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:05:17	 |           null          |                1 (opt-in)          | -> will be removed
-- |    33713	 |       Exclusivity	    |   2019-04-24 21:05:17	 |    2019-04-24 21:05:35  |                1 (opt-out)         |
-- ----------------------------------------------------------------------------------------------------------------------------------
    SELECT
        id_special_condition,
        special_condition_type,
        DATE(ts_opted_in) AS dt_opted_in,
        MAX(DATE(ts_opted_out)) AS dt_opted_out
    FROM 
        datalake_ebdb_clean.special_condition_aud
    WHERE 
        special_condition_status IN ('OptedIn', 'OptedOut')
        AND special_condition_type IN ('Exclusivity', 'OriginalsReady', 'OriginalsReno', 'ORent', 'IRent')
    GROUP BY 1, 2, 3
),
special_conditions AS (
--------------------------------------------------------------------------------------------------------
-- Include flags of special condition (exclusivity and originals)                                     --
--------------------------------------------------------------------------------------------------------
    SELECT
        hsc.id_house,
        scp.special_condition_type,
        scp.dt_opted_in,
        MAX(scp.dt_opted_out) AS dt_opted_out
    FROM 
        datalake_ebdb_clean.house_special_condition AS hsc
    JOIN datalake_ebdb_clean.special_condition AS sc
        ON hsc.id_special_condition = sc.id
    JOIN special_conditions_prev AS scp
        ON scp.id_special_condition = sc.id
    GROUP BY 1, 2, 3
),
listing_special_conditions AS (
-- selecting the last time a listing had its special condition changed on its version
-- example:
-- ----------------------------------------------------------------------------------
-- |  id_house_listing  |  special_condition_type  |  dt_opted_in  |  dt_opted_out  |
-- ----------------------------------------------------------------------------------
-- |    892812943001    |      OriginalsReady      |   2019-03-04  |   2019-05-12   | -> will be removed
-- |    892812943001    |      OriginalsReady      |   2019-05-13  |      null      |
-- ----------------------------------------------------------------------------------
    SELECT
        hl.id_house_listing,
        hl.country_code,
        sc.special_condition_type,
        MAX(sc.dt_opted_in) AS dt_opted_in,
        MAX(sc.dt_opted_out) AS dt_opted_out
    FROM 
        datalake_ebdb_listing.house_listing_category AS hl
    JOIN 
        special_conditions AS sc
            ON hl.id_house = sc.id_house
            AND GREATEST(sc.dt_opted_in, DATE(hl.ts_listing_version_start)) >= DATE(hl.ts_listing_version_start)
            AND GREATEST(sc.dt_opted_in, DATE(hl.ts_listing_version_start)) < COALESCE(DATE(hl.ts_listing_version_end), DATE(NOW()))
            AND COALESCE(sc.dt_opted_out, DATE(NOW())) >= COALESCE(DATE(hl.ts_listing_version_end), DATE(NOW()))
            AND COALESCE(sc.dt_opted_out, DATE(NOW())) >= DATE(hl.ts_listing_version_start)
    GROUP BY 1, 2, 3
)
-- in case a house listing has more than one Special Condition types: exclusivity, ready and reno on the same version
SELECT
    id_house_listing,
    country_code,
    special_condition_type,
    dt_opted_in,
    dt_opted_out,
    -- selecting the maximum opt-in/out of a house listing, not considering the Originals' type and ioRents' type
    ROW_NUMBER() OVER (
                        PARTITION BY 
                            id_house_listing,
                            CASE 
                                WHEN special_condition_type LIKE 'Originals%' THEN 'Originals'
                                WHEN special_condition_type LIKE '%Rent' THEN 'ioRent'
                                ELSE special_condition_type
                            END 
                        ORDER BY dt_opted_in DESC, COALESCE(dt_opted_out, DATE('2100-01-01')) DESC
    ) AS rn_last_special_condition,
    ROW_NUMBER() OVER (
                        PARTITION BY 
                            id_house_listing,
                            CASE 
                                WHEN special_condition_type LIKE 'Originals%' THEN 'Originals'
                                WHEN special_condition_type LIKE '%Rent' THEN 'ioRent'
                                ELSE special_condition_type
                            END
                        ORDER BY dt_opted_in ASC, COALESCE(dt_opted_out, DATE('2100-01-01')) ASC
    ) AS rn_first_special_condition
FROM 
    listing_special_conditions