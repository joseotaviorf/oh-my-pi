WITH deduped AS (
    SELECT
        id,
        business_unit_id AS id_business_unit,
        region_id AS id_region,
        business_context,
        version,
        created_at AS ts_created,
        updated_at AS ts_updated,
        year,
        month,
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.business_unit_region
)
SELECT
    id,
    id_business_unit,
    id_region,
    business_context,
    version,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    deduped
WHERE
    rn = 1
