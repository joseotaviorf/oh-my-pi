SELECT /*+ RANGE_JOIN(hch, 340) */
    hl.id_house_listing,
    hl.id_house,
    hch.id_enrollment,
    hch.id_partner,
    hch.id_user,
    hch.consultant_type,
    ROW_NUMBER() OVER(PARTITION BY hl.id_house_listing ORDER BY hch.rev) AS enrollment_number,
    MAX(hch.rev) OVER(PARTITION BY hl.id_house_listing) = hch.rev AS is_last_ciq_on_listing,
    hch.dt_consultant_started,
    ts_consultant_deleted,
    ts_enrollment_started,
    ts_enrollment_ended,
    ts_listing_version_start,
    ts_listing_version_end
FROM
    datalake_ebdb_listing.house_listing AS hl
LEFT JOIN
    datalake_big_agent.house_consultant_history AS hch
        ON hl.id_house = hch.id_house
        AND (
                (hch.ts_enrollment_started >= hl.ts_listing_version_start AND  hch.ts_enrollment_started < COALESCE(hl.ts_listing_version_end, '2100-04-01'))
                OR (hl.ts_listing_version_start >= hch.ts_enrollment_started AND hl.ts_listing_version_start < COALESCE(hch.ts_enrollment_ended, '2100-04-01'))
            )
WHERE
    hch.is_last_status_of_day = True