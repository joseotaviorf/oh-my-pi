-- The following query brings data from 2.0 database
SELECT
        py.id * -1 AS id_house,
        CAST(NULL AS STRING) AS type,
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
        datalake_rental_guarantee_platform_clean.fiancavelo_property AS py
    LEFT JOIN
        datalake_ebdb_clean.country AS ct
            ON IF(REPLACE(py.country, '\'', '') = '', NULL, UPPER(REPLACE(py.country, '\'', ''))) = UPPER(ct.name)
    LEFT JOIN
        datalake_ebdb_clean.state AS st
            ON UPPER(py.state) = UPPER(st.name)
            AND ct.id = st.id_country
