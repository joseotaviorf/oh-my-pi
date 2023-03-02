SELECT 
    name AS metric_name,
    project AS project_name,
    project_version,    
    REPLACE(value:["@quintoandar/cozy-core"],'^','') AS core,
    REPLACE(value:["@quintoandar/cozy-icons"],'^','') AS icons,
    REPLACE(value:["@quintoandar/cozy-theme"],'^','') AS theme,
    REPLACE(value:["@quintoandar/cozy-tokens"],'^','') AS tokens,
    REPLACE(value:["@quintoandar/cozy-utils"],'^','') AS utils,
    DATE(created_at) AS dt_created
FROM datalake_cozy_metrics_raw.library_versions
WHERE created_at IS NOT NULL