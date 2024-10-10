WITH dim_region AS (
  SELECT 
    sk_region,
    TRIM(name) AS neighborhood,
    city_group,
    city_name,
    country_name
  FROM 
    dw_public.dim_region
),
regions AS (
  SELECT
    r.sk_region,
    r.neighborhood,
    r.city_group,
    r.city_name,
    CASE 
    ----------
    -- RMSP --
    ----------
    -- SP Capital
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Bela Vista') THEN ARRAY('Bela Vista', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Água Branca') THEN ARRAY('Água Branca', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Vila Mariana') THEN ARRAY('Vila Mariana', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Pinheiros') THEN ARRAY('Pinheiros', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Jardim Paulista') THEN ARRAY('Jardim Paulista', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Santa Cecília') THEN ARRAY('Santa Cecília', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Consolação') THEN ARRAY('Consolação', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN('Vila Leopoldina') THEN ARRAY('Vila Leopoldina', '1 specific neighborhood')
    -- SP.5 - Centro, Mooca, Tatuapé, Cambuci (+42 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Mooca') THEN ARRAY('Mooca', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Tatuapé','Parque Novo Mundo','Penha de França') 
      OR r.neighborhood LIKE '%Parque Novo Mundo%' THEN ARRAY('Tatuapé', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Cambuci') THEN ARRAY('Cambuci', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Ipiranga') THEN ARRAY('Ipiranga', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Liberdade') THEN ARRAY('Liberdade', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Bosque da Saúde', 'Jardim Miriam') THEN ARRAY('Bosque da Saúde', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Prudente', 'Vila Santa Clara', 'Vila Invernada', 'Jardim Anália Franco') 
      OR r.neighborhood LIKE '%Jardim Avelino%' THEN ARRAY('Vila Prudente', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila das Mercês') THEN ARRAY('Vila das Mercês', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Belém') THEN ARRAY('Belém', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Carrão', 'Vila Matilde', 'Vila Aricanduva', 'Jardim Maringá') THEN ARRAY('Vila Carrão', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Formosa', 'Vila Antonieta', 'Jardim Teresa', 'Jardim Nove de Julho', 'Jardim Aricanduva', 'Chácara Mafalda') THEN ARRAY('Vila Formosa', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Cangaíba') THEN ARRAY('Cangaíba', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Ema', 'Vila Mendes', 'Vila Macedópolis', 'Jardim Independência') THEN ARRAY('Vila Ema', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Sacomã', 'Parque Bristol', 'Jardim Santa Emília') THEN ARRAY('Sacomã', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Esperança', 'Vila Ré', 'Vila Guilhermina', 'Vila Nova Curuca', 'Vila Curuca') THEN ARRAY('Vila Esperança', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Centro', 'Canindé', 'Pari', 'Brás', 'Campos Elíseos') THEN ARRAY('Centro', 'neighborhood cluster')
    -- SP.2 - Itaquera, Sapopemba, Vila Califórnia, Vila Alpina (+29 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Itaquera', 'Conjunto Residencial Jose Bonifacio', 'Jardim Brasília', 'Vila Progresso', 'Parque Casa de Pedra', 'Vila Pedroso', 'Parque Savoy City', 'Cidade Lider') 
      THEN ARRAY('Itaquera', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Sapopemba', 'Parque São Lucas', 'Parque Residencial Oratório', 'Vila Carmosina', 'Vila Industrial', 'Jardim Mimar', 'Jardim Cinco de Julho') 
      THEN ARRAY('Sapopemba', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Veleiros', 'Capela do Socorro', 'Cidade Dutra', 'Interlagos', 'Jardim Botucatu', 'Jardim Cristal', 'Jardim Marabá', 'Vila Arriete', 'Vila Emir', 'Vila Lisboa',
      'Jardim dos Lagos', 'Jardim Paquetá', 'Jurubatuba', 'Jardim Santa Helena', 'Jardim Ipanema', 'Vila Gea') 
      OR r.neighborhood LIKE '%Vila da Paz%' THEN ARRAY('Veleiros', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND R.neighborhood IN ('Vila Califórnia', 'Vila Alpina') THEN ARRAY('Vila Califórnia', 'neighborhood cluster')
    -- SP.1 - Artur Alvim, Ponte Rasa, Ermelino Matarazzo, Vila Jacuí (+10 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Ermelino Matarazzo', 'Vila Penteado') THEN ARRAY('Ermelino Matarazzo','neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Artur Alvim', 'Cidade Patriarca', 'Jardim Santa Maria', 'Vila Dalila', 'Vila Nhocuné', 'Vila Nova Savoia', 'Vila Talarico', 'Vila Euthalia', 'Jardim Arize') THEN ARRAY('Artur Alvim','neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Ponte Rasa') THEN ARRAY('Ponte Rasa', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Jacuí') THEN ARRAY('Vila Jacuí', '1 specific neighborhood')
    -- SP.4 - Butantã, Brooklin, Panamby, Campo Belo (+41 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Brooklin', 'Planalto Paulista') THEN ARRAY('Brooklin', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Panamby') THEN ARRAY('Panamby', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Butantã', 'Jardim Éster Yolanda', 'Jaguaré', 'Cidade São Francisco', 'City América', 'Parque São Domingos', 'Parque dos Príncipes', 'Jardim Santo Elias') 
      OR r.neighborhood LIKE '%Cidade São Francisco%' THEN ARRAY('Butantã', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Andrade', 'Jardim Nadir', 'Jardim Londrina', 'Jardim Taboão', 'Parque Esmeralda', 'Parque Reboucas') THEN ARRAY('Vila Andrade','neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Jabaquara')
      OR r.neighborhood LIKE '%Vila Clara%' THEN ARRAY('Jabaquara', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Portal do Morumbi', 'Morumbi', 'Vila Sônia', 'Real Parque', 'Jardim Jussara', 'Jardim Monte Kemel', 'Jardim Vazani', 'Fazenda Morumbi') 
      OR (r.neighborhood LIKE '%Cidade Jardim%' AND  r.city_name = 'São Paulo') OR r.neighborhood LIKE '%Jardim Guedala%' THEN ARRAY('Portal do Morumbi', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Mascote') THEN ARRAY('Vila Mascote', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Jardim Marajoara') THEN ARRAY('Jardim Marajoara', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Campo Belo') THEN ARRAY('Campo Belo','1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Chácara Santo Antonio') THEN ARRAY('Chácara Santo Antonio', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Santo Amaro', 'Jardim São Savério', 'Vila Campestre', 'Socorro', 'Campo Grande', 'Jardim Palmares', 'Vila Campo Grande', 'Vila Romano', 'Jardim Guarapiranga', 
      'Jardim Nosso Lar','Jardim Campo Grande','Vila Isa') 
      OR r.neighborhood LIKE '%Jardim Sao Luis%' OR r.neighborhood LIKE '%Santo Amaro%' OR r.neighborhood LIKE '%Jardim Marajoara%' THEN ARRAY('Santo Amaro', 'neighborhood cluster')
    -- SP.3 - Pinheiros, Vila Mariana, Santa Cecília, Bela Vista (+31 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Moema') THEN ARRAY('Moema', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Saúde', 'Jardim Vergueiro') THEN ARRAY('Saúde', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Aclimação') THEN ARRAY('Aclimação', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Olímpia', 'Itaim Bibi', 'Vila Nova Conceição') THEN ARRAY('Vila Olímpia', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Barra Funda') THEN ARRAY('Barra Funda', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Chácara Inglesa') THEN ARRAY('Chácara Inglesa', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Madalena', 'Alto de Pinheiros', 'Jardim América', 'Jardim Europa', 'Jardim Paulistano') THEN ARRAY('Vila Madalena', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Perdizes', 'Higienópolis', 'Pacaembu') THEN ARRAY('Perdizes', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Bom Retiro') THEN ARRAY('Bom Retiro', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Pompéia') THEN ARRAY('Vila Pompéia', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Romana', 'Alto da Lapa', 'Lapa') THEN ARRAY('Vila Romana', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Paraíso') THEN ARRAY('Paraíso', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Sumaré') THEN ARRAY('Sumaré', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Clementino', 'Jardim Avelino') THEN ARRAY('Vila Clementino', 'neighborhood cluster')
    -- SP.0 - Santana, Água Fria, Freguesia do Ó, Mandaqui (+24 bairros)
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Santana', 'Vila Ede', 'Vila Maria', 'Vila Sabrina') 
      OR r.neighborhood LIKE '%Vila Sabrina%' OR r.neighborhood LIKE '%Vila Maria%' THEN ARRAY('Santana', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND (r.neighborhood) IN ('Freguesia do Ó', 'Piqueri', 'Vila Mangalot', 'Vila Jaguara') 
      OR r.neighborhood LIKE '%Vila Miriam%' OR r.neighborhood LIKE '%Parque Anhanguera%' THEN ARRAY('Freguesia do Ó', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Casa Verde', 'Vila Santista', 'Vila Santa Maria', 'Jardim Primavera', 'Casa Verde Alta', 'Vila Prado', 'Vila Diva') THEN ARRAY('Casa Verde', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Vila Guilherme') THEN ARRAY('Vila Guilherme', '1 specific neighborhood')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Mandaqui', 'Tucuruvi', 'Vila Nova Cachoeirinha', 'Vila Roque', 'Sítio do Mandaqui', 'Vila Dionísia', 'Vila Amália', 'Lauzane Paulista', 'Vila Constança') 
      OR r.neighborhood LIKE '%Jardim Peri%' OR r.neighborhood LIKE '%Jardim Virginia Bianca%' OR r.neighborhood LIKE '%Jardim Brasil%' THEN ARRAY('Mandaqui', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Água Fria', 'Vila Mazzei', 'Vila Gustavo', 'Jardim Brasil') 
      OR r.neighborhood LIKE '%Vila Constança%' THEN ARRAY('Água Fria', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND r.neighborhood IN ('Jardim Iris', 'Jardim Felicidade', 'Jaraguá', 'Jardim Pirituba') THEN ARRAY('Jardim Iris', 'neighborhood cluster')
    WHEN r.city_name = 'São Paulo' AND cl.cluster_name != 'Sem Cluster' THEN ARRAY(cl.cluster_name, 'neighborhood cluster')
    -- Grande SP
    WHEN r.city_group = 'RMSP' AND r.city_name IN ('São Bernardo do Campo', 'Santo André', 'São Caetano do Sul','Diadema', 'Mauá','Jardim Santa Adelia','Vila Liviero') THEN ARRAY('ABCDM', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.city_name IN ('Osasco', 'Taboão da Serra', 'Carapicuíba') THEN ARRAY('Osasco e Taboão da Serra', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.neighborhood IN ('Jardim do Lago','Jardim das Esmeraldas') THEN ARRAY('Osasco e Taboão da Serra', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.city_name IN ('Barueri', 'Santana de Parnaíba') THEN ARRAY('Barueri e Santana de Parnaíba', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.city_name IN ('Guarulhos') THEN ARRAY('Guarulhos', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.city_name IN ('Jundiaí', 'Várzea Paulista') THEN ARRAY('Jundiaí e Varzea Paulista', 'metropolitan area without core city')
    WHEN r.city_group = 'RMSP' AND r.city_name != 'São Paulo' THEN ARRAY('Grande São Paulo', 'metropolitan area without core city')
    --------------------
    -- RIO DE JANEIRO --
    --------------------
    -- RJ.1 - Irajá, Penha, Olaria, Ramos (+7 bairros)
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Olaria', 'Penha', 'Ramos', 'Bonsucesso', 'Benfica', 'Penha Circular') THEN ARRAY('Olaria and 5 specific neighborhood', 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Irajá', 'Jardim America', 'Brás de Pina', 'Cordovil', 'Parada de Lucas') THEN ARRAY('Irajá and 4 specific neighborhood', 'neighborhood cluster')
    -- RJ.2 - Méier, Engenho Novo, Cachambi, Piedade (+9 bairros)
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Méier', 'Madureira', 'Quintino Bocaiúva', 'Cascadura', 'Abolição', 'Todos os Santos', 'Engenho de Dentro', 'Engenho Novo', 'Piedade') THEN ARRAY('Méier and 5 specific neighborhood', 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Cachambi', 'Del Castilho', 'Inhaúma', 'Engenho da Rainha', 'Pilares') THEN ARRAY('Cachambi and 5 specific neighborhood', 'neighborhood cluster')
    -- RJ.4 - Tijuca, Botafogo, Centro, Flamengo (+7 bairros)
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Centro','Cidade Nova','Rio Comprido','Santa Teresa','Estácio') THEN ARRAY('Centro and 4 specific neighborhood', 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Botafogo','Flamengo','Glória','Laranjeiras','Catete') THEN ARRAY('Botafogo and 4 specific neighborhood', 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Tijuca','Maracanã') THEN ARRAY('Tijuca and 1 specific neighborhood', 'neighborhood cluster')
    -- RJ.8 - Freguesia, Taquara, Jacarepaguá, Pechincha (+3 bairros)
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Freguesia','Jacarepaguá','Anil','Curicica','Itanhangá') 
      OR (r.neighborhood LIKE '%Freguesia%' AND r.city_name = 'Rio de Janeiro') THEN ARRAY('Freguesia and 4 specific neighborhood', 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' AND r.neighborhood IN ('Taquara', 'Pechincha') THEN ARRAY('Taquara and 1 specific neighborhood', 'neighborhood cluster')
    WHEN r.neighborhood IN ('Vargem Pequena', 'Vargem Grande', 'Joá') THEN ARRAY('RJ.9 - Recreio, Jardim Oceânico, Barra da Tijuca, São Conrado (+1 bairro)', 'neighborhood cluster')
    WHEN cl.cluster_name = 'RJ.9 - Recreio, Jardim Oceânico, Barra da Tijuca, São Conrado (+1 bairro)' THEN ARRAY('RJ.9 - Recreio, Jardim Oceânico, Barra da Tijuca, São Conrado (+1 bairro)', 'neighborhood cluster')
    WHEN cl.cluster_name IN ('RJ.0 - Copacabana, Ipanema, Leblon, Lagoa (+4 bairros)', 'RJ.5 - Jardim Guanabara, Portuguesa, Urca, Jardim Carioca (+1 bairro)', 
    'RJ.3 - Praia da Bandeira, Ribeira, Pitangueiras, Zumbi', 'RJ.6 - Vargem Pequena, Vargem Grande, Madureira') 
      AND r.neighborhood NOT IN ('Portuguesa', 'Jardim Carioca', 'Moneró', 'Praia da Bandeira', 'Pitangueiras', 'Zumbi', 'Ribeira', 'Jardim Guanabara') 
      OR (r.neighborhood IN ('Copacabana') AND r.city_name = 'Rio de Janeiro') THEN ARRAY('Zona Sul Rio', 'several neighborhood clusters')
    WHEN cl.cluster_name LIKE 'RJ%' AND cl.cluster_name NOT IN ('RJ.9 - Recreio, Jardim Oceânico, Barra da Tijuca, São Conrado (+1 bairro)') THEN ARRAY(cl.cluster_name, 'neighborhood cluster')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' THEN ARRAY('Rio de Janeiro Capital', 'defaulting to capital city name')
    WHEN r.city_group IN ('Rio de Janeiro') AND r.city_name != 'Rio de Janeiro' THEN ARRAY('Grande Rio de Janeiro', 'metropolitan area without core city')
    ------------------
    -- PORTO ALEGRE --
    ------------------
    WHEN r.city_group IN ('Porto Alegre') AND r.city_name = 'Porto Alegre' THEN ARRAY('Porto Alegre Capital', 'capital city only')
    WHEN r.city_group IN ('Porto Alegre') AND r.city_name != 'Porto Alegre' THEN ARRAY('Grande Porto Alegre', 'metropolitan area without core city')
    --------------
    -- CAMPINAS --
    --------------
    WHEN r.city_group IN ('Campinas') THEN ARRAY('Campinas', 'core city with metropolitan area')
    --------------------
    -- BELO HORIZONTE --
    --------------------
    WHEN r.city_group IN ('Belo Horizonte') AND r.city_name = 'Belo Horizonte' THEN ARRAY('Belo Horizonte', 'capital city only')
    WHEN r.city_group IN ('Belo Horizonte') AND r.city_name != 'Belo Horizonte' THEN ARRAY('Grande Belo Horizonte', 'metropolitan area without core city')
    ELSE ARRAY(city_group, 'ELSE city group (defaulting)')
  END AS region_group_array
  FROM
    dim_region AS r
  LEFT JOIN 
    datalake_gsheets_clean.for_sale_marketplace_region_clusters AS cl 
      ON r.sk_region = cl.id_region
  WHERE 
    r.country_name = 'Brazil'
),
unpacking_region_group AS (
  SELECT
    sk_region,
    neighborhood,
    city_name,
    city_group,
    ELEMENT_AT(region_group_array, 1) AS region_group,
    ELEMENT_AT(region_group_array, 2) AS region_group_type
  FROM 
    regions
),
region_display_name AS ( 
  SELECT
    sk_region,
    neighborhood,
    city_name,
    city_group,
    region_group,
    region_group_type,
    CASE
      WHEN region_group_type = '1 specific neighborhood' THEN region_group
      WHEN region_group_type = 'metropolitan area without core city' THEN CONCAT(city_name, ' e região')
      WHEN region_group_type = 'core city with metropolitan area' THEN CONCAT(city_name, ' e região')
      WHEN region_group_type = 'capital city only' THEN city_name
      WHEN region_group_type = 'neighborhood cluster' THEN CONCAT(neighborhood, ' e região')
      WHEN region_group_type = 'several neighborhood clusters' THEN CONCAT(neighborhood, ' e região')
    END AS region_display_name
  FROM 
    unpacking_region_group
),
active_for_sale_city_groups AS (
    SELECT 
      r.city_group,
      COUNT(DISTINCT sk_house) AS listings_publisheds
    FROM 
      dw_sale.fact_listings AS f
    INNER JOIN
      dw_sale.dim_listing AS d
        USING(sk_house)
    INNER JOIN 
      dw_public.dim_region AS r
        USING(sk_region)
    WHERE
      d.status = 'PUBLISHED'
    GROUP BY 
      1
    HAVING 
      listings_publisheds >= 100
),
quintoandar_transactions AS (
  SELECT
    sk_house,
    r.region_group,
    sa.sale_price_agreed / NULLIF(h.total_area, 0) AS price_per_m2,
    DATE(DATE_TRUNC('quarter', sa.ts_sale_agreement_signed)) AS dt_quarter_ccv
  FROM
    dw_sale.fact_offers AS o
  INNER JOIN 
    dw_sale.dim_sale_agreement AS sa
      USING(sk_offer)
  INNER JOIN 
    dw_house.dim_house AS h
      USING(sk_house)
  INNER JOIN 
    region_display_name AS r 
      USING(sk_region)
  INNER JOIN 
    active_for_sale_city_groups AS c 
      USING(city_group)
  WHERE 
    sa.ts_sale_agreement_signed IS NOT NULL
    AND sa.sale_price_agreed BETWEEN 50000 AND 20000000
),
itbi_transactions AS (
  SELECT 
    t.id_itbi_transaction,
    r.region_group,
    t.declared_transaction_value / NULLIF(t.built_area_m2, 0) AS price_per_m2,
    DATE(DATE_TRUNC('quarter', t.dt_transaction)) AS dt_quarter_ccv
  FROM 
    datalake_open_external_data.itbi_all_residential_transactions AS t
  INNER JOIN 
    region_display_name AS r 
      ON t.id_region = r.sk_region
  INNER JOIN 
    active_for_sale_city_groups AS c 
      ON c.city_group = r.city_group
  WHERE 
    t.property_type IN ('Residencial Horizontal','Residencial Vertical')
    AND t.declared_transaction_value BETWEEN 50000 AND 20000000
),
all_transactions AS (
  SELECT
    sk_house AS id,
    'quintoandar' AS transaction_source,
    region_group,
    price_per_m2,
    dt_quarter_ccv
  FROM 
    quintoandar_transactions
  UNION ALL 
  SELECT
    id_itbi_transaction AS id,
    'itbi' AS transaction_source,
    region_group,
    price_per_m2,
    dt_quarter_ccv
  FROM 
    itbi_transactions
),
transactions_median_prices AS (
  SELECT 
    region_group,
    COUNT(DISTINCT id) AS ccvs,
    APPROX_PERCENTILE(price_per_m2, 0.50) AS median_price_per_m2,
    APPROX_PERCENTILE(IF(transaction_source = 'itbi', price_per_m2, NULL), 0.5) AS itbi_median_price_per_m2,
    APPROX_PERCENTILE(IF(transaction_source = 'quintoandar', price_per_m2, NULL), 0.5) AS quintoandar_median_price_per_m2
  FROM 
    all_transactions
  GROUP BY 
    1
),
itbi_price_factor_to_adjust AS (
  SELECT 
    region_group, 
    ((quintoandar_median_price_per_m2 / itbi_median_price_per_m2) - 1) - (((quintoandar_median_price_per_m2 / itbi_median_price_per_m2) - 1) * 0.15) AS itbi_factor 
  FROM 
    transactions_median_prices 
  WHERE
    itbi_median_price_per_m2 IS NOT NULL
),
all_transactions_adjusted AS (
  SELECT
    id,
    transaction_source,
    region_group,
    IF(transaction_source = 'itbi', (price_per_m2 + (price_per_m2 * itbi_factor)), price_per_m2) AS price_per_m2,
    dt_quarter_ccv
  FROM
    all_transactions AS t
  LEFT JOIN 
    itbi_price_factor_to_adjust AS f
      USING(region_group)
  WHERE
    price_per_m2 < 50000
    AND dt_quarter_ccv >= DATE('2019-01-01')
),
median_price_by_region AS (
  SELECT 
    region_group,
    dt_quarter_ccv,
    ROUND(APPROX_PERCENTILE(price_per_m2, 0.50), 0) AS median_price_per_m2
  FROM
    all_transactions_adjusted
  GROUP BY 
    1, 2
),
tabular_data AS (
  SELECT 
    r.sk_region AS id_region,
    r.city_group,
    r.city_name AS city,
    r.neighborhood, 
    region_group AS tier,
    r.region_group_type AS tier_type,
    r.region_display_name AS region_used_for_m2_average,
    DATE_FORMAT(p.dt_quarter_ccv, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ccv_period,
    DATE_FORMAT(ADD_MONTHS(p.dt_quarter_ccv, 2), "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ccv_end_period,
    CASE 
      WHEN d.month =  1 THEN 'Mar/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  4 THEN 'Jun/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  7 THEN 'Set/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  10 THEN 'Dez/' || RIGHT(CAST(d.year AS STRING), 2)
    END AS period_name,
    p.median_price_per_m2 AS avg_price_m2
  FROM 
    region_display_name AS r
  LEFT JOIN 
    median_price_by_region AS p
      USING(region_group)
  INNER JOIN 
    dw_public.dim_date AS d
      ON p.dt_quarter_ccv = d.date
  WHERE
    r.sk_region != -1
    AND ADD_MONTHS(p.dt_quarter_ccv, 2) <= DATE_TRUNC('MONTH', CURRENT_DATE)
),
result_format AS (
  SELECT 
      id_region, 
      city_group,
      city,
      neighborhood, 
      tier,
      tier_type,
      region_used_for_m2_average,
      COLLECT_LIST(STRUCT(period_name, ccv_period, ccv_end_period, avg_price_m2)) AS data
  FROM
    tabular_data
  GROUP BY 
      1, 2, 3, 4, 5, 6, 7
)
SELECT 
  CONCAT(UNIX_TIMESTAMP(), LPAD(CAST(ROW_NUMBER() OVER (ORDER BY id_region) AS STRING), 6, '0')) AS id,
  id_region, 
  city_group,
  city,
  neighborhood, 
  tier,
  tier_type,
  region_used_for_m2_average,
  data,
  DATE_FORMAT(CURRENT_TIMESTAMP, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ts_load
FROM 
  result_format