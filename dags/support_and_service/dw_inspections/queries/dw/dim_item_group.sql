WITH item_group_comments AS (
    SELECT
        i.id_item_group,
        SUM(
            INT(
                CASE
                    WHEN ii.id_item_issue IS NOT NULL AND i.display_type in ('CHECK_DESCRIPTION', 'CHECK') THEN TRUE
                    ELSE FALSE
                END
            )
        ) > 0 AS has_item_checklist,
        SUM(
            INT(
                CASE
                    WHEN ii.id_item_issue IS NOT NULL AND i.display_type in ('CHIP_CHOICE_SINGLE', 'OVERVIEW_WITH_CONDITIONS') THEN TRUE
                    ELSE FALSE
                END
            )
        ) > 0 AS has_item_chip_choice,
        SUM(
            INT(
                CASE
                    WHEN i.comment IS NOT NULL AND i.item_type IN ('overview','other') THEN TRUE
                    WHEN ii.issue_comment IS NOT NULL THEN TRUE
                    ELSE FALSE
                END
            )
        ) > 0 AS has_inspector_open_comment
    FROM
        datalake_inspections.item AS i
    LEFT JOIN
        datalake_inspections.item_issue AS ii
            ON ii.id_item = i.id_item
    WHERE
        i.year = {year}
        AND i.month = {month}
        AND i.day = {day}
    GROUP BY 1
)
SELECT DISTINCT
    ig.id_item_group AS sk_item_group,
    ig.item_group_name,
    ig.item_group_type,
    ig.status,
    COALESCE(igc.has_item_checklist, FALSE) AS has_item_checklist,
    COALESCE(igc.has_item_chip_choice, FALSE) AS has_item_chip_choice,
    COALESCE(igc.has_inspector_open_comment, FALSE) AS has_inspector_open_comment,
    ig.is_inferior_quality,
    ig.ts_created,
    ig.ts_updated,
    NOW() AS ts_load,
    ig.year,
    ig.month,
    ig.day
FROM
    datalake_inspections.item_group AS ig
LEFT JOIN
    item_group_comments AS igc
        ON igc.id_item_group = ig.id_item_group
WHERE
    MAKE_DATE(ig.year, ig.month, ig.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
