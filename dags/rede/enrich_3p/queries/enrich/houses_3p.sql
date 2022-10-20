SELECT
    h.id AS id_house,
    h.internal_admin_info,
    partner_3p_supply AS partner,
    NOW() AS ts_load
FROM
    datalake_ebdb_listing.house AS h
WHERE
    UPPER(h.internal_admin_info) LIKE '%[3P-%]%'