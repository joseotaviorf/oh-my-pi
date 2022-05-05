SELECT
    CAST(COALESCE(r.id, ar.id) AS BIGINT) AS id,
    c.id AS id_city,
    mr.id AS id_macro_region,
    CAST(st.id_country AS INTEGER) AS id_country,
    r.level,
    COALESCE(r.name, ar.neighbourhood) AS name,
    mr.name AS macro_region_name,
    COALESCE(ar.city, c.name) AS city_name,
    ar.city_group,
    CAST(ar.ddd AS STRING) AS city_ddd,
    ar.region_code,
    ar.region_code_deprecated,
    ar.region_code_inspector,
    ar.state AS short_region_name,
    CASE
        WHEN COALESCE(c.name, ar.city) IN ('Rio de Janeiro', 'Campinas') THEN COALESCE(c.name, ar.city)
        WHEN COALESCE(c.name, ar.city) IN
          ('São Paulo', 'São Bernardo do Campo', 'São Caetano do Sul', 'Santo André', 'Guarulhos', 'Osasco', 'Barueri') THEN 'Grande São Paulo'
        ELSE NULL
    END AS greater_region,
    ar.regional,
    ar.regional_deprecated,
    ar.regional_inspection,
    ar.tier,
    CASE
      WHEN st.id_country = 1 THEN 'Brazil'
      WHEN st.id_country = 2 THEN 'Mexico'
    END AS country_name,
    (r.level = 'Cidade') AS is_city,
    r.ts_created,
    r.ts_updated
FROM
  datalake_ebdb_clean.region AS r
LEFT JOIN
  datalake_ebdb_clean.region AS mr
    ON mr.id = r.id_parent_region
LEFT JOIN
  datalake_ebdb_clean.region AS c
    ON c.id = mr.id_parent_region
LEFT JOIN
  datalake_ebdb_clean.state AS st
    ON st.id = COALESCE(r.id_state, mr.id_state, c.id_state)
LEFT JOIN
  datalake_gsheets_clean.auxiliary_region AS ar
    ON r.id = ar.id