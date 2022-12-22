SELECT
  c.id AS id_company,
  COALESCE(c.comercial_name, c.name) AS company_name,
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
  c.document AS cnpj
FROM
  datalake_velo_clean.clientes_company AS c
LEFT JOIN
  datalake_velo_clean.clientes_address AS ca
    ON ca.id = c.address
