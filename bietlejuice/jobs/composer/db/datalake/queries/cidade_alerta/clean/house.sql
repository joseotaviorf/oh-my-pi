-- Some fields are JSON strings. We're using REGEX because it's not possible to use get_json_object because of the special characters.

select
    regexp_extract(_id, '(\\w+\\d+)', 1) as _id,    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
    regexp_extract(aluguel, '(\\d+(,\\d{2})?)', 1) as rental,   -- format: ["2930"]
    regexp_extract(aluguel_condominio, '(\\d+(,\\d{2})?)', 0) as condo_rental,  -- format: ["3855"]
    amenidades as amenities,
    regexp_extract(andar, '\\["(.+)"\\]', 1) as floor,  -- format: ["2"]
    regexp_extract(area, '(\\d+(,\\d{2})?)', 0) as area,    -- format: ["70"]
    regexp_extract(bairro, '\\["(.+)"\\]', 1) as neighborhood,  -- format: ["Pinheiros"]
    regexp_extract(banheiros, '(\\d+)', 1) as bathrooms,    -- format: ["2"]
    regexp_extract(cidade, '\\["(.+)"\\]', 1) as city,  -- format: ["São Paulo"]
    regexp_extract(condominio, '(\\d+(,\\d{2})?)', 0) as condo_price,   -- format: ["950"]
    regexp_extract(condominio_id, '(\\d+)', 1) as id_condo, -- format: ["1997"]
    regexp_extract(custo, '(\\d+(,\\d{2})?)', 0) as cost,   -- format: ["3881"]
    regexp_extract(descricao, '\\["(.+)"\\]', 1) as description,    -- format: ["Condomínio com piscina, academia."]
    regexp_extract(endereco,  '\\["(.+)"\\]', 1) as address,    -- format: ["Rua São Joaquim"]
    cast(regexp_extract(first_publication, '(\\d{4}-\\d{2}-\\d{2}\\w{1}\\d{2}:\\d{2}:\\d{2})', 0) as timestamp) as ts_first_publication,    -- format {"$date": "2019-05-01T10:00:00Z" }
    regexp_extract(foto_capa, '\\["(.+)"\\]', 1) as cover_photo,    -- format: ["capa892808390348_1999252778405MG9338.jpg"]
    garantias as guarantees,
    regexp_extract(home_insurance, '(\\d+(,\\d{2})?)', 0) as home_insurance, -- format: ["26"]
    house_id as id_house,
    regexp_extract(id, '\\["(.+)"\\]', 1) as id,    -- format: {"$oid": "5b9ffb4da939ee6a2c873276"}
    instalacoes as facilities,
    regexp_extract(iptu, '(\\d+(,\\d{2})?)', 0) as iptu,    -- format: ["0"]
    listing_tags,
    regexp_extract(local, '\\["(.+)"\\]', 1) as local,  -- format: ["-23.5602898,-46.6847615"]
    regexp_extract(nome_condominio, '\\["(.+)"\\]', 1) as condo_name,   -- format: ["Vivaldi"]
    photo_titles,
    photos,
    regexp_extract(quartos, '\\["(.+)"\\]', 1) as bedrooms, -- format: ["2"]
    regexp_extract(regiao, '\\["(.+)"\\]', 1) as region,    -- format: ["São Paulo > Brooklin > Brooklin"]
    regexp_extract(regiao_nome, '\\["(.+)"\\]', 1) as region_name,  -- format: ["Vila Prudente"]
    regexp_extract(relevance_score, '\\["(.+)"\\]', 1) as relevance_score,  -- format: ["1000"]
    regexp_extract(relevance_score_vnext, '\\["(.+)"\\]', 1) as relevance_score_vnext,  -- format: ["1000"]
    regexp_extract(short_id,'\\["(.+)"\\]', 1) as id_short, -- format: ["108390"]
    special_conditions,
    regexp_extract(suites, '\\["(.+)"\\]', 1) as suites,    -- format: ["1"]
    regexp_extract(tipo, '\\["(.+)"\\]', 1) as type,    -- format: ["Apartamento"]
    cast(regexp_extract(ultima_publicacao, '(\\d{4}-\\d{2}-\\d{2}\\w{1}\\d{2}:\\d{2}:\\d{2})', 0) as timestamp) as ts_last_publication, -- format {"$date": "2019-05-01T10:00:00Z" }
    regexp_extract(vagas, '\\["(.+)"\\]', 1) as vacancies,  -- format: ["1"]
    cast(regexp_extract(verificado, '\\["(.+)"\\]', 1) as boolean) as is_verified,  -- format: ["true"]
    regexp_extract(visit_status, '\\["(.+)"\\]', 1) as visit_status -- format: ["ACCEPT_NEW"]
from
    datalake_cidade_alerta_raw.house
