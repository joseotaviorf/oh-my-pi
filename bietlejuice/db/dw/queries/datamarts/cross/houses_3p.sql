SELECT
    CAST(h.id AS VARCHAR) AS sk_house,
    CAST(h.internal_admin_info AS VARCHAR) AS internal_admin_info,
    partner_3p_supply AS partner,
    CAST(NOW() AS VARCHAR) AS ts_load
FROM
    datalake_ebdb_listing_prod.house AS h
WHERE
    UPPER(h.internal_admin_info) LIKE '%[3P-%]%'