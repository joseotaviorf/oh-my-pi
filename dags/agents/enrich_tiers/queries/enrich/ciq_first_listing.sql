-- Do not reprocess the table, as the source tables are still fully loaded
WITH filter_bimester AS (
    SELECT DISTINCT
        ad.bimester_start,
        ad.bimester_end,
        ad.bimester,
        ad.year
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
ciq_first_listing AS (
    SELECT DISTINCT
        hslc.id_house,
        hslc.id_user,
        hslc.consultant_type,
        lbc.ts_first_listing,
        GREATEST(lbc.ts_first_listing, TIMESTAMP(hslc.ts_enrollment_started), TIMESTAMP(hslc.dt_consultant_started)) AS ts_updated
    FROM
        datalake_big_agent.house_sale_listing_consultant AS hslc
    JOIN
        datalake_ebdb_listing.listing_business_context AS lbc
            ON lbc.id_house = hslc.id_house
            AND lbc.business_context = 'SALE'
    WHERE
        hslc.is_last_ciq_on_listing = True
        AND hslc.consultant_type IN ('CIQ_FULL', 'CIQ_MANAGER')
)
SELECT
    cfl.id_house,
    cfl.id_user,
    cfl.consultant_type,
    cfl.ts_first_listing,
    cfl.ts_updated,
    fb.year,
    fb.bimester
FROM
    ciq_first_listing AS cfl
JOIN
    filter_bimester AS fb
        ON DATE(cfl.ts_updated) BETWEEN fb.bimester_start AND fb.bimester_end