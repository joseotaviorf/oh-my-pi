WITH exploded_justifications AS (
  SELECT
      id AS id_answer,
      justifications,
      EXPLODE(FROM_JSON(justifications, 'array<string>')) AS just_json
  FROM 
      datalake_tracksale.answer
  WHERE 
      justifications != '[]'  
),
main_justifications AS (
    SELECT
        id_answer,
        'main' AS level,
        GET_JSON_OBJECT(just_json, '$.name') AS justification,
        JSON_OBJECT_KEYS(GET_JSON_OBJECT(just_json, '$.name'))[0] AS region_language
    FROM 
        exploded_justifications
),
exploded_second_justifications AS (
    SELECT
        id_answer,
        'second' AS level,
        FROM_JSON(GET_JSON_OBJECT(just_json, '$.children'), 'array<string>') AS justification,
        JSON_OBJECT_KEYS(GET_JSON_OBJECT(just_json, '$.name'))[0] AS region_language 
    FROM 
        exploded_justifications
    WHERE 
        GET_JSON_OBJECT(just_json, '$.children') <> '[]'
),
second_justifications AS (
    SELECT 
        id_answer,
        level,
        EXPLODE(justification) AS justification,
        region_language
    FROM 
        exploded_second_justifications
),
justifications AS (
    SELECT * FROM main_justifications
    UNION ALL
    SELECT * FROM second_justifications
)
SELECT 
    id_answer,
    level,
    GET_JSON_OBJECT(justification, concat('$.', region_language)) AS justification
FROM 
    justifications
