SELECT
  r.id AS id_broker, -- id da imobiliaria
  COALESCE(c.comercial_name, c.name) AS broker_name, -- Nome da imobiliaria
  UPPER(ca.city) AS city,
  CASE UPPER(ca.state)
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
    ELSE UPPER(ca.state)
  END AS state,
  UPPER(REPLACE(ca.country, '\'', '')) AS country,
  ca.zipcode,
  ca.geolocation,
  r.creci,
  c.document AS cnpj,
  r.is_active AS is_broker_active,
  r.ts_inserted AS ts_created
FROM
  datalake_velo_clean.fiancavelo_realestate AS r
LEFT JOIN
  datalake_velo_clean.clientes_company AS c
    ON c.id = r.id_company
LEFT JOIN
  datalake_velo_clean.clientes_address AS ca
    ON ca.id = c.address
