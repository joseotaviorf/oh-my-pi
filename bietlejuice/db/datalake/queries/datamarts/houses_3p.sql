SELECT
    h.id AS sk_house,
    h.internal_admin_info,
    REGEXP_EXTRACT(h.internal_admin_info, '(?<=\[3P\-)(.+?)(?=\])') AS partner
FROM
    datalake_ebdb_listing_prod.house AS h
WHERE
    h.internal_admin_info LIKE '%[3P-%]%'