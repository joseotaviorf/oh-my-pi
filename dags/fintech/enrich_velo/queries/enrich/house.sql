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
  py.geolocation
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
