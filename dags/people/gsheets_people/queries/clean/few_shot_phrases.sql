SELECT
    NULLIF(pillar, '') AS pillar,
    NULLIF(points_reference, '') AS points_reference,
    NULLIF(sentiment, '') AS sentiment,
    NULLIF(complexity, '') AS complexity,
    NULLIF(phrase, '') AS phrase,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.few_shot_phrases
WHERE
    phrase IS NOT NULL
    AND phrase <> ''
