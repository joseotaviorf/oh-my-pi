SELECT
    CAST(h.id AS VARCHAR) AS sk_house,
    CAST(h.internal_admin_info AS VARCHAR) AS internal_admin_info,
    CAST(REGEXP_EXTRACT(h.internal_admin_info, '(?<=\[3P\-)(.+?)(?=\])') AS VARCHAR) AS partner,
    CAST(NOW() AS VARCHAR) AS ts_load
FROM
    datalake_ebdb_listing_prod.house AS h
WHERE
    h.internal_admin_info LIKE '%[3P-%]%'