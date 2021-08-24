WITH unnested_tags AS (
    SELECT
        id AS id_answer,
        ts_answer_sent_local,
        EXPLODE(FROM_JSON(tags,'array<string>')) AS tag
    FROM datalake_tracksale.answer
),
tags AS (
  SELECT
    id_answer,
    ts_answer_sent_local,
    GET_JSON_OBJECT(tag, '$.name') AS tag_name,
    GET_JSON_OBJECT(tag, '$.value') AS tag_value
  FROM unnested_tags
)
SELECT
  id_answer,
  ts_answer_sent_local,
  tag_name,
  CASE 
    WHEN tag_name = 'Cidade' AND RLIKE(tag_value, '^[a-zA-Zà-úÀ-Ú]') = False THEN NULL
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('sp','sao paulo', 'sã£o paulo','são paulo - sp', 'su00e3o paulo') THEN 'São Paulo'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) LIKE ('%são paulo%') THEN 'São Paulo'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('rj') THEN 'Rio de Janeiro'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) LIKE '%rio de janeiro%' THEN 'Rio de Janeiro'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('mg') THEN 'Minas Gerais'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('rs', 'rio grande') THEN 'Rio Grande do Sul'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('pr') THEN 'Parana'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('bsb', 'brasilia' ) THEN 'Brasília'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) LIKE '%abc%' THEN 'RMSP'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('grande são paulo') THEN 'RMSP'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('osasco/barueri', 'barueri', 'bareuri') THEN 'Barueri'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('taubaté33') THEN 'Taubaté'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('santo andre', 'santo andru00e9') THEN 'Santo André'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('valinhos - sp', 'valinhos-sp' ) THEN 'Valinhos'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('santana de parnaiba') THEN 'Santana De Parnaíba'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('sao bernardo do campo', 'sao bernardo do campo - sp', 'são bernardo do campo - sp', 'su00e3o bernardo do campo') THEN 'São Bernardo do Campo'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('su00e3o caetano do sul') THEN 'São Caetano do Sul'    
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('niteroi') THEN 'Niterói'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('goiania') THEN 'Goiânia'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('go') THEN 'Goiás'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('camp') THEN 'Campinas'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('porto alegre, florianópolis') THEN 'Porto Alegre'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('sc') THEN 'Santa Catarina'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('florianopolis') THEN 'Florianópolis'
    WHEN tag_name = 'Cidade' AND LOWER(tag_value) IN ('rescisão','negociação','#n/a', 'contrato','verificar', '-', 'way', ' ') THEN NULL
    ELSE tag_value
  END AS tag_value
FROM tags