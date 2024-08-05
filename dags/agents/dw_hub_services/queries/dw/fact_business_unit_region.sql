WITH business_unit_region_aud AS (
    SELECT 
        bura.id,
        XXHASH64(bura.id, bura.id_region, bura.id_business_unit) AS id_business_region,
        bura.id_business_unit,
        bura.id_region,
        bura.rev_end,
        COALESCE(
          rev.ts_created, 
          LEAD(bura.ts_created) OVER(PARTITION BY bura.id_region, bura.id_business_unit ORDER BY bura.ts_updated)
        ) AS ts_ended,
        bura.ts_created,
        bura.ts_updated
    FROM
        datalake_hub_services_clean.business_unit_region_aud AS bura
    LEFT JOIN 
        datalake_hub_services_clean.rev_info AS rev 
            ON rev.id = bura.rev_end
            AND rev.ts_created >= bura.ts_created
),
business_unit_region_ended AS (
    SELECT
        bura.id_business_region,
        FIRST(bura.ts_created) AS ts_operations_started,
        LAST(bura.ts_ended) FILTER (WHERE bura.ts_ended IS NOT NULL) AS ts_operations_ended,
        LAST(bura.ts_updated) AS ts_updated
    FROM
        business_unit_region_aud AS bura
    GROUP BY ALL
    ORDER BY ts_updated
)
SELECT DISTINCT
    bura.id_business_region AS sk_business_unit_region,
    bura.id_business_unit AS sk_business_unit,
    bura.id_region AS sk_region,
    bur.id IS NOT NULL AS is_active,
    bure.ts_operations_started AS ts_operations_started,
    IF(bur.id IS NULL, bure.ts_operations_ended, NULL) AS ts_operations_ended,
    NOW() AS ts_load
FROM 
    business_unit_region_aud AS bura
LEFT JOIN
    business_unit_region_ended AS bure
        ON bure.id_business_region = bura.id_business_region
LEFT JOIN
    datalake_hub_services_clean.business_unit_region AS bur
        ON bur.id = bura.id
        AND bur.id_region = bura.id_region
        AND bur.id_business_unit = bura.id_business_unit