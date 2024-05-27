SELECT
    id_profile AS sk_profile,
    profile AS member_profile,
    dt_created,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_hub_services.profile AS p
WHERE
    dt_created = MAKE_DATE({year}, {month}, {day})