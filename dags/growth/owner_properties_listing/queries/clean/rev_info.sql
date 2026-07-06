SELECT
    rev,
    TO_TIMESTAMP(CAST(revtstmp / 1000 AS BIGINT)) AS ts_created,
    year,
    month,
    day
FROM
    datalake_owner_properties_listing_raw.revinfo
