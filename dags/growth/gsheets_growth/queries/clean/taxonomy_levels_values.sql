SELECT
    NULLIF(taxonomy_level,'') AS taxonomy_level,
    NULLIF(value,'') AS value,
    NULLIF(TO_DATE(dt_created, 'yyyy-MM-dd'),'') AS dt_created,
    NULLIF(TO_DATE(dt_updated, 'yyyy-MM-dd'),'') AS dt_updated
FROM
    datalake_gsheets_raw.taxonomy_levels_values