SELECT
    pp.id AS id_house,
    pt.name AS type,
    a.street,
    a.`number`,
    IF(a.complement='', NULL, a.complement) AS complement,
    a.neighborhood,
    a.city,
    COALESCE(st.abbreviation, IF(a.state = '', NULL, UPPER(a.state))) AS state,
    ct.code AS country_code,
    a.zip_code AS zipcode,
    NULL AS geolocation,
    FALSE AS is_legacy
FROM
    datalake_rental_guarantee_platform_clean.property_propose AS pp
LEFT JOIN
    datalake_rental_guarantee_platform_clean.property_type AS pt
    ON pp.id_property_type = pt.id
LEFT JOIN
    datalake_rental_guarantee_platform_clean.address AS a
    ON pp.id_address = a.id
LEFT JOIN
    datalake_ebdb_clean.country AS ct
        ON IF(REPLACE(a.country, '\'', '') = '', NULL, UPPER(REPLACE(a.country, '\'', ''))) = UPPER(ct.name)
LEFT JOIN
    datalake_ebdb_clean.state AS st
        ON UPPER(a.state) = UPPER(st.name)
        AND ct.id = st.id_country
