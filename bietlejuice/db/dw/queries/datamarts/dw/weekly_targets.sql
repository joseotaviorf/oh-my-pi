SELECT
    cast(week_start_date as timestamp) as week_start_date,
    city,
    channel,
    medium,
    cast(opportunity_target as numeric(10,2)) as opportunity_target,
    cast(listing_target as numeric(10,2)) as listing_target
FROM
    datalake_raw.weekly_targets