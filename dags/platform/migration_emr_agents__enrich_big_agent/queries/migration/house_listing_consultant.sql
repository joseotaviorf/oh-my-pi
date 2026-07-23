WITH sale_historical_consultant AS (
    SELECT /*+ RANGE_JOIN(hch, 340) */
        sl.id_sale_listing,
        sl.id_house,
        hch.id_enrollment,
        hch.id_partner,
        hch.id_user,
        hch.consultant_type,
        FIRST_VALUE(consultant_type) IGNORE NULLS OVER(PARTITION BY sl.id_sale_listing ORDER BY hch.rev) AS first_consultant_type,
        -- If we don't have a consultant related to one listing
        -- we still needing to propagate that there isnt information
        -- about consultant for this listing, and this is the last
        -- status on this listing. So COALESCE.
        COALESCE(MAX(hch.rev) OVER(PARTITION BY sl.id_sale_listing) = hch.rev, True) AS is_last_ciq_on_listing,
        MAX(IF(hch.consultant_type = 'CIQ_FULL', True, False)) OVER(PARTITION BY sl.id_house) AS was_ciq_full,
        hch.dt_consultant_started,
        hch.ts_consultant_deleted,
        hch.ts_enrollment_started,
        hch.ts_enrollment_ended
    FROM
        datalake_sale_listings.sale_listing AS sl
    LEFT JOIN
        datalake_big_agent.house_consultant_history AS hch
            ON sl.id_house = hch.id_house
    WHERE
        hch.is_last_status_of_day = True
),
rent_historical_consultant AS (
    SELECT /*+ RANGE_JOIN(hch, 340) */
        hl.id_house_listing,
        hl.id_house,
        hch.id_enrollment,
        hch.id_partner,
        hch.id_user,
        hch.consultant_type,
        FIRST_VALUE(consultant_type) IGNORE NULLS OVER(PARTITION BY hl.id_house_listing ORDER BY hch.rev) AS first_consultant_type,
        -- If we don't have a consultant related to one listing
        -- we still needing to propagate that there isnt information
        -- about consultant for this listing, and this is the last
        -- status on this listing. So COALESCE.
        COALESCE(MAX(hch.rev) OVER(PARTITION BY hl.id_house_listing) = hch.rev, True) AS is_last_ciq_on_listing,
        MAX(IF(hch.consultant_type = 'CIQ_FULL', True, False)) OVER(PARTITION BY hl.id_house) AS was_ciq_full,
        hch.dt_consultant_started,
        hch.ts_consultant_deleted,
        hch.ts_enrollment_started,
        hch.ts_enrollment_ended,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    LEFT JOIN
        datalake_ebdb_listing.house as ho
            ON hl.id_house = ho.id
    LEFT JOIN
        datalake_big_agent.house_consultant_history AS hch
            ON hl.id_house = hch.id_house
            AND (
                    (hch.ts_enrollment_started >= COALESCE(hl.ts_listing_version_start,ho.dt_creation) AND  hch.ts_enrollment_started < COALESCE(hl.ts_listing_version_end, '2100-04-01'))
                    OR 
                    (COALESCE(hl.ts_listing_version_start,ho.dt_creation) >= hch.ts_enrollment_started AND COALESCE(hl.ts_listing_version_start,ho.dt_creation) < COALESCE(hch.ts_enrollment_ended, '2100-04-01'))
                )
            AND hch.is_last_status_of_day = True
)
SELECT 
    id_house_listing AS id_listing,
    id_house,
    id_enrollment,
    id_partner,
    id_user,
    /*
    There are some rules between what is historical on 
    our operational database (BIG AGENT) and what should
    be attributed on the analytcal side. They are:
    1. If there isn't a consultant related to this listing,
        but it was CIQ_FULL once, then it will be CIQ_FULL. 
        puff.
    2. We don't have a default program for agents out of 
        these programs. In this case, it is set to "Core".
    3. If a program is deleted or has the enrollment ended
        (that is deleted too XD) within a listing, we
        set it to Core too.
    */
    CASE 
        WHEN consultant_type IS NULL AND was_ciq_full THEN 'CIQ_FULL'
        WHEN consultant_type IS NULL OR (consultant_type <> 'CIQ_FULL' AND ts_enrollment_ended < COALESCE(ts_listing_version_end, '2100-01-01')) THEN 'Core'
        ELSE consultant_type
    END AS consultant_type,
    CASE
        WHEN first_consultant_type IS NULL AND was_ciq_full THEN 'CIQ_FULL'
        WHEN first_consultant_type IS NULL THEN 'Core'
        ELSE first_consultant_type
    END AS first_consultant_type,
    "RENT" AS business_context,
    is_last_ciq_on_listing,
    dt_consultant_started,
    ts_consultant_deleted,
    ts_enrollment_started,
    ts_enrollment_ended,
    ts_listing_version_start,
    ts_listing_version_end
FROM
    rent_historical_consultant
UNION
SELECT 
    id_sale_listing AS id_listing,
    id_house,
    id_enrollment,
    id_partner,
    id_user,
    /*
    There are some rules between what is historical on 
    our operational database (BIG AGENT) and what should
    be attributed on the analytcal side. They are:
    1. If there isn't a consultant related to this listing,
        but it was CIQ_FULL once, then it will be CIQ_FULL. 
        puff.
    2. We don't have a default program for agents out of 
        these programs. In this case, it is set to "Core".
        Specifically, this rule is not applicable here
        because we don't have the concept of time
        on sale listing, it is an ilusion. Puff
    3. If a program is deleted or has the enrollment ended
        (that is deleted too XD) within a listing, we
        set it to Core too.
    */
    CASE 
        WHEN consultant_type IS NULL AND was_ciq_full THEN 'CIQ_FULL'
        WHEN consultant_type IS NULL THEN 'Core'
        ELSE consultant_type
    END AS consultant_type,
    CASE
        WHEN first_consultant_type IS NULL AND was_ciq_full THEN 'CIQ_FULL'
        WHEN first_consultant_type IS NULL THEN 'Core'
        ELSE first_consultant_type
    END AS first_consultant_type,
    "SALE" AS business_context,
    is_last_ciq_on_listing,
    dt_consultant_started,
    ts_consultant_deleted,
    ts_enrollment_started,
    ts_enrollment_ended,
    NULL AS ts_listing_version_start,
    NULL AS ts_listing_version_end
FROM
    sale_historical_consultant