SELECT
  py.id AS id_house,
  pyt.name AS type, -- tipo da propriedade: Casa, Apto, Kitnet
  IF(py.city = '', NULL, UPPER(py.city)) AS city,
  CASE UPPER(py.state)
    WHEN 'ACRE' THEN 'AC'
    WHEN 'ALAGOAS' THEN 'AL'
    WHEN 'AMAPÁ' THEN 'AP'
    WHEN 'AMAZONAS' THEN 'AM'
    WHEN 'BAHIA' THEN 'BA'
    WHEN 'CEARÁ' THEN 'CE'
    WHEN 'DISTRITO FEDERAL' THEN 'DF'
    WHEN 'ESPÍRITO SANTO' THEN 'ES'
    WHEN 'GOIÁS' THEN 'GO'
    WHEN 'MARANHÃO' THEN 'MA'
    WHEN 'MATO GROSSO' THEN 'MT'
    WHEN 'MATO GROSSO DO SUL' THEN 'MS'
    WHEN 'MINAS GERAIS' THEN 'MG'
    WHEN 'PARÁ' THEN 'PA'
    WHEN 'PARAÍBA' THEN 'PB'
    WHEN 'PARANÁ' THEN 'PR'
    WHEN 'PERNAMBUCO' THEN 'PE'
    WHEN 'PIAUÍ' THEN 'PI'
    WHEN 'RIO DE JANEIRO' THEN 'RJ'
    WHEN 'RIO GRANDE DO NORTE' THEN 'RN'
    WHEN 'RIO GRANDE DO SUL' THEN 'RS'
    WHEN 'RONDÔNIA' THEN 'RO'
    WHEN 'RORAIMA' THEN 'RR'
    WHEN 'SANTA CATARINA' THEN 'SC'
    WHEN 'SÃO PAULO' THEN 'SP'
    WHEN 'SERGIPE' THEN 'SE'
    WHEN 'TOCANTINS' THEN 'TO'
    ELSE IF(py.state = '', NULL, UPPER(py.state))
  END AS state,
  IF(REPLACE(py.country, '\'', '') = '', NULL, UPPER(REPLACE(py.country, '\'', ''))) AS country,
  IF(py.zipcode = '', NULL, UPPER(py.zipcode)) AS zipcode,
  py.geolocation
FROM
  datalake_velo_clean.fiancavelo_property AS py
LEFT JOIN
  datalake_velo_clean.fiancavelo_propertytype AS pyt
    ON pyt.id = py.id_property_type
      AND pyt.is_active
