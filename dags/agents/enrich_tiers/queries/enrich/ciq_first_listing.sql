WITH house_listing_consultant AS (
    SELECT 
        hslc.id_house,
        hslc.id_user,
        hslc.consultant_type,
        "SALE" AS business_context,
        hslc.is_last_ciq_on_listing,
        hslc.ts_enrollment_started
    FROM
        datalake_big_agent.house_sale_listing_consultant AS hslc
    UNION
    SELECT 
        hrlc.id_house,
        hrlc.id_user,
        hrlc.consultant_type,
        "RENT" AS business_context,
        hrlc.is_last_ciq_on_listing,
        hrlc.ts_enrollment_started
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
    SELECT
        hlc.id_house,
        hlc.id_user,
        COALESCE(so.id_offer, rde.id_offer) AS if_offer,
        hlc.consultant_type,
        lbc.status,
        lbc.business_context,
        lbc.ts_first_listing IS NOT NULL AND (
            u.ts_first_unpublished IS NOT NULL
            AND DATE_DIFF(u.ts_first_unpublished, lbc.ts_first_listing) < 14 
            AND COALESCE(so.dt_sale_agreement_signed, rde.ts_event) IS NULL
        ) IS FALSE AS is_valid_first_listing,
        COALESCE(so.dt_sale_agreement_signed, rde.ts_event) AS ts_contract_signed,
        lbc.ts_first_listing,
        u.ts_first_unpublished,
        CASE
            WHEN 
                COALESCE(so.dt_sale_agreement_signed, rde.ts_event) IS NOT NULL
                AND COALESCE(so.dt_sale_agreement_signed, rde.ts_event) < lbc.ts_first_listing + INTERVAL 14 DAY
                THEN COALESCE(so.dt_sale_agreement_signed, rde.ts_event)
            ELSE lbc.ts_first_listing + INTERVAL 14 DAY 
        END AS ts_valid_first_listing,
        GREATEST(
            lbc.ts_first_listing, 
            TIMESTAMP(hlc.ts_enrollment_started), 
            COALESCE(so.dt_sale_agreement_signed, rde.ts_event),            
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
            AND lbc.ts_first_listing <= so.dt_sale_agreement_signed
            AND hlc.business_context = "SALE"
    LEFT JOIN
        datalake_rent_demand_events.rent_demand_events AS rde
            ON rde.id_house = hlc.id_house
            AND lbc.ts_first_listing <= rde.ts_event
            AND hlc.business_context = "RENT"
            AND rde.id_event_type = 9
    WHERE
        hlc.is_last_ciq_on_listing = True
        AND hlc.id_user IS NOT NULL
        AND hlc.consultant_type IN ('CIQ_FULL', 'CIQ_MANAGER')
),
first_contract_signed AS (
    SELECT
        cfl.id_house,
        cfl.id_user,
        cfl.if_offer,
        cfl.business_context,
        cfl.ts_contract_signed
    FROM
        ciq_first_listing AS cfl
    WHERE
        cfl.ts_contract_signed IS NOT NULL
    QUALIFY
        1 = ROW_NUMBER() OVER (PARTITION BY cfl.id_house, cfl.id_user, cfl.business_context ORDER BY cfl.ts_contract_signed)
)
SELECT
    cfl.id_house,
    CAST(cfl.id_user AS BIGINT) AS id_user,
    pa.id_partner,
    u.id_agent,
    u.uuid_person,
    cfl.consultant_type,
    cfl.business_context,
    cfl.status,
    cfl.ts_first_listing IS NOT NULL AS has_first_listing,
    cfl.is_valid_first_listing,
    cfl.ts_first_listing,
    cfl.ts_first_unpublished,
    cfl.ts_contract_signed,
    cfl.ts_valid_first_listing,
    MAX(cfl.ts_updated) AS ts_updated,
    YEAR(MAX(cfl.ts_updated)) AS year,
    MONTH(MAX(cfl.ts_updated)) AS month,
    DAY(MAX(cfl.ts_updated)) AS day
FROM
    ciq_first_listing AS cfl
LEFT JOIN
    first_contract_signed AS fcs
        ON fcs.id_house = cfl.id_house
        AND fcs.id_user = cfl.id_user
        AND fcs.business_context = cfl.business_context
LEFT JOIN
    datalake_ebdb_user.user AS u
        ON u.id = cfl.id_user
LEFT JOIN
    datalake_ebdb_clean.partner_agent AS pa
        ON pa.id_user = cfl.id_user
WHERE
    DATE(cfl.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND (
        fcs.id_house IS NULL
        OR fcs.ts_contract_signed = cfl.ts_contract_signed
    )
GROUP BY ALL