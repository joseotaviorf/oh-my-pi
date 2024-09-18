SELECT
    geoTargetConstant.id AS id_geo_target,
    geoTargetConstant.name,
    geoTargetConstant.canonicalName AS canonical_name,
    geoTargetConstant.countryCode AS country_code,
    geoTargetConstant.parentGeoTarget AS parent_geo_target,
    geoTargetConstant.resourceName AS resource_name,
    geoTargetConstant.status AS status,
    geoTargetConstant.targetType AS target_type
FROM
    datalake_google_ads_raw.geo_target_constant
GROUP BY ALL
