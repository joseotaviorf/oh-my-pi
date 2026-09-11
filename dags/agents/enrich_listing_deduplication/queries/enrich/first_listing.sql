WITH house_listing_consultant AS (
    SELECT
        hlc.id_house,
        hlc.id_user,
        hlc.consultant_type,
        hlc.business_context,
        hlc.is_last_ciq_on_listing,
        CAST(
            CASE
                WHEN hlc.business_context = 'RENT' THEN COALESCE(
                    hlc.ts_enrollment_started,
                    FIRST(hlc.ts_listing_version_start) OVER (
                        PARTITION BY hlc.id_house, hlc.business_context, COALESCE(hlc.id_user, -1), hlc.consultant_type
                        ORDER BY hlc.ts_listing_version_start ASC
                    )
                )
                ELSE hlc.ts_enrollment_started
            END AS TIMESTAMP
        ) AS ts_enrollment_started
    FROM
        datalake_big_agent.house_listing_consultant AS hlc
    WHERE
        hlc.id_user IS NOT NULL
        OR hlc.consultant_type = 'Core'
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
    GROUP BY 1, 2
),
first_listing AS (
    SELECT
        hlc.id_house,
        COALESCE(hlc.id_user, -1) AS id_user,
        hlc.consultant_type,
        lbc.status,
        lbc.business_context,
        hlc.ts_enrollment_started,
        COALESCE(so.ts_sale_agreement_signed, rde.ts_event) AS ts_contract_signed,
        lbc.ts_first_listing,
        u.ts_first_unpublished,
        GREATEST(
            lbc.ts_first_listing,
            hlc.ts_enrollment_started,
            COALESCE(so.ts_sale_agreement_signed, rde.ts_event),
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
        datalake_sale_offer.sale_offer AS so
            ON so.id_house = hlc.id_house
            AND lbc.ts_first_listing <= so.ts_sale_agreement_signed
            AND hlc.business_context = "SALE"
    LEFT JOIN
        datalake_rent_demand_events.rent_demand_events AS rde
            ON rde.id_house = hlc.id_house
            AND lbc.ts_first_listing <= rde.ts_event
            AND hlc.business_context = "RENT"
            AND rde.id_event_type = 9
    WHERE
        hlc.is_last_ciq_on_listing IS TRUE
),
first_contract_signed AS (
    SELECT
        cfl.id_house,
        cfl.id_user,
        cfl.business_context,
        cfl.ts_contract_signed,
        ROW_NUMBER() OVER (
            PARTITION BY cfl.id_house, cfl.id_user, cfl.business_context
            ORDER BY cfl.ts_contract_signed
        ) = 1 AS is_first_contract_signed
    FROM
        first_listing AS cfl
    WHERE
        cfl.ts_contract_signed IS NOT NULL
),
house_first_listing AS (
    SELECT
        cfl.id_house,
        cfl.id_user,
        cfl.consultant_type,
        cfl.business_context,
        cfl.status,
        cfl.ts_first_listing IS NOT NULL AS has_first_listing,
        cfl.ts_first_listing,
        cfl.ts_first_unpublished,
        cfl.ts_contract_signed,
        cfl.ts_enrollment_started,
        MAX(cfl.ts_updated) AS ts_updated,
        YEAR(MAX(cfl.ts_updated)) AS year,
        MONTH(MAX(cfl.ts_updated)) AS month,
        DAY(MAX(cfl.ts_updated)) AS day
    FROM
        first_listing AS cfl
    LEFT JOIN
        first_contract_signed AS fcs
            ON fcs.id_house = cfl.id_house
            AND fcs.id_user = cfl.id_user
            AND fcs.business_context = cfl.business_context
            AND fcs.is_first_contract_signed IS TRUE
    WHERE
        fcs.id_house IS NULL
        OR fcs.ts_contract_signed = cfl.ts_contract_signed
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
),
deduped_house_first_listing AS (
    SELECT
        hfl.id_house,
        hfl.id_user,
        hfl.consultant_type,
        hfl.business_context,
        hfl.status,
        hfl.has_first_listing,
        hfl.ts_first_listing,
        hfl.ts_first_unpublished,
        hfl.ts_contract_signed,
        hfl.ts_enrollment_started,
        hfl.ts_updated,
        hfl.year,
        hfl.month,
        hfl.day,
        ROW_NUMBER() OVER (
            PARTITION BY hfl.id_house, hfl.business_context, hfl.consultant_type, hfl.ts_first_listing
            ORDER BY hfl.ts_enrollment_started ASC, hfl.ts_updated DESC
        ) = 1 AS is_house_first_listing
    FROM
        house_first_listing AS hfl
)
SELECT 
    hfl.id_house,
    hfl.id_user,
    hfl.consultant_type,
    hfl.business_context,
    hfl.status,
    hfl.has_first_listing,
    hfl.ts_first_listing,
    hfl.ts_first_unpublished,
    hfl.ts_contract_signed,
    hfl.ts_enrollment_started,
    hfl.ts_updated,
    hfl.year,
    hfl.month,
    hfl.day
FROM 
    deduped_house_first_listing AS hfl
WHERE
    is_house_first_listing IS TRUE
