WITH cte_union AS (
(
    SELECT
        py.id AS id_house,
        pyt.name AS type,
        py.street,
        py.number,
        py.complement,
        py.neighborhood,
        IF(py.city = '', NULL, UPPER(py.city)) AS city,
        COALESCE(st.abbreviation, IF(py.state = '', NULL, UPPER(py.state))) AS state,
        ct.code AS country_code,
        IF(py.zipcode = '', NULL, UPPER(py.zipcode)) AS zipcode,
        py.geolocation,
        TRUE AS is_legacy
    FROM
        datalake_velo_clean.fiancavelo_property AS py
    LEFT JOIN
        datalake_velo_clean.fiancavelo_propertytype AS pyt
            ON pyt.id = py.id_property_type
            AND pyt.is_active
    LEFT JOIN
        datalake_ebdb_clean.country AS ct
            ON IF(REPLACE(py.country, '\'', '') = '', NULL, UPPER(REPLACE(py.country, '\'', ''))) = UPPER(ct.name)
    LEFT JOIN
        datalake_ebdb_clean.state AS st
            ON UPPER(py.state) = UPPER(st.name)
            AND ct.id = st.id_country

)
UNION ALL
(
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
)
ORDER BY 1
)
SELECT
    id_house, -- Confirmar como vai ser o a migração, visto que na 3.0 não começou em 5Mi
    `type`,
    street,
    `number`,
    complement,
    neighborhood,
    city,
    state,
    country_code,
    zipcode,
    geolocation,
    is_legacy
FROM
    cte_union
