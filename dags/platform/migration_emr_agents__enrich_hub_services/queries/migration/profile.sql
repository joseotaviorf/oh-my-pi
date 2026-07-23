WITH profile AS (
    SELECT
        profile,
        DATE(MIN(mp.ts_created)) AS dt_created
    FROM
        datalake_hub_services_clean.member_profile_aud AS mp
    GROUP BY 1
)
SELECT DISTINCT
    XXHASH64(profile) AS id_profile,
    profile,
    dt_created,
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    profile
WHERE
    dt_created = MAKE_DATE({year}, {month}, {day})
