SELECT
    h.id AS id_house,
    h.id_company_hubspot,
    ure.id_user,
    'LISTING_UNPUBLISHED' AS event_type,
    u.email AS user_email,
    h.partner_3p_supply,
    ure.reason AS revision_reason,
    lbc_aud.status_reason,
    lbc_aud.rev,
    ure.id_user IS NOT NULL AS is_manual,
    COUNT(*) OVER (PARTITION BY rev) > 1 AS is_mass_update,
    FROM_UNIXTIME(ts_revision/1000) AS ts_revision
FROM
    datalake_ebdb_listing.house AS h
JOIN
    datalake_ebdb_clean.listing_business_context_aud AS lbc_aud
        ON h.id = lbc_aud.id_house
JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
        ON ure.id = lbc_aud.rev
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON ure.id_user = u.id
WHERE
    lbc_aud.mod_status = '1'
    AND lbc_aud.business_context = 'SALE'
    AND h.is_3p_supply
    AND rev_type = 1
    AND lbc_aud.status = 'UNPUBLISHED'
UNION ALL
SELECT
    h.id AS id_house,
    h.id_company_hubspot,
    ure.id_user,
    'HOUSE_UPDATED' AS event_type,
    u.email AS user_email,
    h.partner_3p_supply,
    ure.reason AS revision_reason,
    NULL::STRING AS status_reason,
    h_aud.rev,
    ure.id_user IS NOT NULL AS is_manual,
    COUNT(*) OVER (PARTITION BY rev) > 1 AS is_mass_update,
    FROM_UNIXTIME(ts_revision/1000) AS ts_revision
FROM
    datalake_ebdb_listing.house AS h
JOIN
    datalake_ebdb_clean.house_aud AS h_aud
        ON h.id = h_aud.id_house
JOIN
    datalake_ebdb_clean.user_revision_entity AS ure
        ON ure.id = h_aud.rev
LEFT JOIN
    datalake_ebdb_clean.user AS u
        ON ure.id_user = u.id
WHERE
    h.is_3p_supply
    AND rev_type = 1
