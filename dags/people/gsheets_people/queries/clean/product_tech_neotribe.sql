-- Product and Technology neotribe catalog from the team-formation workbook.
-- Sheet tab "2. Teams, Mission & Goals" uses header_row 4 (Line/Neotribe/Objective/Mission/Scope).
-- Grain is one row per line × neotribe. Blank cells become NULL. Rows without
-- line or neotribe, and leftover header labels, are dropped. Column A is an
-- empty spacer in the sheet and is not selected.
SELECT
    MD5(
        CONCAT_WS(
            ',',
            CAST(NULLIF(TRIM(line), '') AS STRING),
            CAST(NULLIF(TRIM(neotribe), '') AS STRING)
        )
    ) AS id_line_neotribe,
    NULLIF(TRIM(line), '') AS line,
    NULLIF(TRIM(neotribe), '') AS neotribe,
    NULLIF(TRIM(objective), '') AS objective,
    NULLIF(TRIM(mission), '') AS mission,
    NULLIF(TRIM(scope), '') AS scope,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.product_tech_neotribe
WHERE
    NULLIF(TRIM(line), '') IS NOT NULL
    AND NULLIF(TRIM(neotribe), '') IS NOT NULL
    AND LOWER(TRIM(line)) <> 'line'
    AND LOWER(TRIM(neotribe)) <> 'neotribe'
