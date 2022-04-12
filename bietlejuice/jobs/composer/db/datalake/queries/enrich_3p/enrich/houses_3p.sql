SELECT
    h.id AS id_house,
    h.internal_admin_info,
    REGEXP_EXTRACT(h.internal_admin_info, '(?<=\\[3P\\-)(.+?)(?=\\])') AS partner,
    NOW() AS ts_load
FROM
    datalake_ebdb_listing.house AS h
WHERE
    h.internal_admin_info LIKE '%[3P-%]%'