SELECT
    keyword,
    CAST(dt_effective_start AS DATE) AS dt_effective_start,
    CAST(dt_effective_end AS DATE) AS dt_effective_end
FROM
    datalake_gsheets_raw.seo_goldenset
