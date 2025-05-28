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
        "SALE" AS business_context,
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
        "RENT" AS business_context,
        hrlc.is_last_ciq_on_listing,
        hrlc.ts_enrollment_started,
        hrlc.dt_consultant_started
    FROM
        datalake_big_agent.house_rent_listing_consultant AS hrlc
),
unpublished AS (
    SELECT 
        lbc_aud.id_house,
        lbc_aud.business_context,
        MIN(ure.ts_revision) AS ts_first_unpublished
    FROM
        datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
    JOIN
        datalake_ebdb_user.user_revision_entity AS ure
            ON ure.id = lbc_aud.rev
    WHERE
        status = 'UNPUBLISHED'
        AND mod_status = 1
    GROUP BY ALL
),
ciq_first_listing AS (
    /**  
        The First Listing is valid after 14 days from its publication date. 
        Example: if it was published on the 1st of the month, and remained published until the 15th, 
        then it will be considered valid on this date.
    **/
    SELECT DISTINCT
        hlc.id_house,
        hlc.id_user,
        hlc.consultant_type,
        lbc.status,
        lbc.business_context,
        lbc.ts_first_listing IS NOT NULL AND (
            u.ts_first_unpublished IS NOT NULL
            AND DATE_DIFF(u.ts_first_unpublished, lbc.ts_first_listing) < 14 
            AND so.dt_sale_agreement_signed IS NULL
        ) IS FALSE AS is_valid_first_listing,
        so.dt_sale_agreement_signed AS ts_sale_agreement_signed,
        lbc.ts_first_listing,
        u.ts_first_unpublished,
        CASE
            WHEN 
                so.dt_sale_agreement_signed IS NOT NULL
                AND so.dt_sale_agreement_signed < lbc.ts_first_listing + INTERVAL 14 DAY
                THEN so.dt_sale_agreement_signed
            ELSE lbc.ts_first_listing + INTERVAL 14 DAY 
        END AS ts_valid_first_listing,
        GREATEST(
            lbc.ts_first_listing, 
            TIMESTAMP(hlc.ts_enrollment_started), 
            TIMESTAMP(hlc.dt_consultant_started), 
            so.dt_sale_agreement_signed,
            u.ts_first_unpublished
        ) AS ts_updated
    FROM
        house_listing_consultant AS hlc
    JOIN
        datalake_ebdb_listing.listing_business_context AS lbc
            ON lbc.id_house = hlc.id_house
            AND lbc.business_context = hlc.business_context
    LEFT JOIN 
        unpublished AS u
            ON u.id_house = hlc.id_house
            AND u.business_context = hlc.business_context
    LEFT JOIN
        datalake_offer.sale_offer AS so
            ON so.id_house = hlc.id_house
            AND hlc.business_context = "SALE"
    WHERE
        hlc.is_last_ciq_on_listing = True
        AND hlc.id_user IS NOT NULL
        AND hlc.consultant_type IN ('CIQ_FULL', 'CIQ_MANAGER')
)
SELECT
    cfl.id_house,
    cfl.id_user,
    cfl.consultant_type,
    cfl.business_context,
    cfl.status,
    cfl.ts_first_listing IS NOT NULL AS has_first_listing,
    cfl.is_valid_first_listing,
    cfl.ts_first_listing,
    cfl.ts_first_unpublished,
    cfl.ts_sale_agreement_signed,
    cfl.ts_valid_first_listing,
    cfl.ts_updated,
    fb.year,
    fb.bimester
FROM
    ciq_first_listing AS cfl
JOIN
    filter_bimester AS fb
        ON DATE(cfl.ts_updated) BETWEEN fb.bimester_start AND fb.bimester_end