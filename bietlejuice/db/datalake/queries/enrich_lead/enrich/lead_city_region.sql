WITH city_region AS (
  SELECT
    r.id AS id_region,
    REGEXP_REPLACE(SF_REMOVE_ACCENTUATION(LOWER(r.name)), '[^a-z]+', '') as formatted_city
  FROM datalake_region.region r
  WHERE r.is_city
),
leads_with_city AS (
    SELECT
        l.id as id_lead,
        REGEXP_REPLACE(SF_REMOVE_ACCENTUATION(LOWER(l.city)), '[^a-z]+', '') AS formatted_city
    FROM datalake_ebdb_clean.lead l
    WHERE l.city IS NOT NULL -- NoneType would throw an exception when using UDF SF_REMOVE_ACCENTUATION
)
SELECT
    l.id_lead,
    r.id_region
FROM leads_with_city l
JOIN city_region r
    ON r.formatted_city = l.formatted_city
