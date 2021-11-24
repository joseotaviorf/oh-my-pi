WITH exploded_justifications AS (
    SELECT
        id AS id_answer,
        justifications,
        explode(FROM_json(justifications, 'array<string>')) AS just_json
    FROM 
        datalake_casa_mineira_tracksale.answer
    WHERE justifications != '[]'  
),
main_justifications AS (
    SELECT
        id_answer,
        'main' AS level,
        GET_JSON_OBJECT(just_json, '$.name') AS justification
    FROM 
        exploded_justifications
),
exploded_second_justifications AS (
    SELECT
        id_answer,
        'second' AS level,
        FROM_json(GET_JSON_OBJECT(just_json, '$.children'), 'array<string>') AS justification    
    FROM 
        exploded_justifications
    WHERE GET_JSON_OBJECT(just_json, '$.children') <> '[]'
),
second_justifications AS (
    SELECT 
        id_answer,
        level,
        explode(justification) AS justification
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
    GET_JSON_OBJECT(justification, '$.pt-br') AS justification
FROM 
    justifications