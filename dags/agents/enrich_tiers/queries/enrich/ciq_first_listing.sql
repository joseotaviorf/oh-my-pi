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
house_listing_consultant AS (
    SELECT 
        hslc.id_house,
        hslc.id_user,
        hslc.consultant_type,
        hslc.is_last_ciq_on_listing,
        hslc.ts_enrollment_started,
        hslc.dt_consultant_started
    FROM
        datalake_big_agent.house_sale_listing_consultant AS hslc
    UNION
    SELECT 
        hrlc.id_house,
        hrlc.id_user,
        hrlc.consultant_type,
        hrlc.is_last_ciq_on_listing,
        hrlc.ts_enrollment_started,
        hrlc.dt_consultant_started
    FROM
        datalake_big_agent.house_rent_listing_consultant AS hrlc
),
ciq_first_listing AS (
    SELECT DISTINCT
        hlc.id_house,
        hlc.id_user,
        hlc.consultant_type,
        lbc.business_context,
        lbc.ts_first_listing,
        GREATEST(lbc.ts_first_listing, TIMESTAMP(hlc.ts_enrollment_started), TIMESTAMP(hlc.dt_consultant_started)) AS ts_updated
    FROM
        house_listing_consultant AS hlc
    JOIN
        datalake_ebdb_listing.listing_business_context AS lbc
            ON lbc.id_house = hlc.id_house
    WHERE
        hlc.is_last_ciq_on_listing = True
        AND hlc.consultant_type IN ('CIQ_FULL', 'CIQ_MANAGER')
)
SELECT
    cfl.id_house,
    cfl.id_user,
    cfl.consultant_type,
    cfl.business_context,
    cfl.ts_first_listing IS NOT NULL AS has_first_listing,
    cfl.ts_first_listing,
    cfl.ts_updated,
    fb.year,
    fb.bimester
FROM
    ciq_first_listing AS cfl
JOIN
    filter_bimester AS fb
        ON DATE(cfl.ts_updated) BETWEEN fb.bimester_start AND fb.bimester_end