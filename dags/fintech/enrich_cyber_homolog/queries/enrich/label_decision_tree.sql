
WITH
union_sources AS (
    SELECT
        *,
        3 AS label_number,
        'Campaign' AS queue_type
    FROM datalake_cyber_clean.campaign_label_decision_tree

    UNION ALL

    SELECT
        *,
        5 AS label_number,
        'Eviction' AS queue_type
    FROM datalake_cyber_clean.eviction_label_decision_tree
),
calculate AS (
    SELECT
        group,
        level,
        test,
        label_number,
        queue_type,
        MAX(CASE WHEN test = 0 AND sequence = -1 THEN comment ELSE NULL END) OVER (PARTITION BY level) AS level_name,
        MAX(CASE WHEN sequence = 1001 THEN queue ELSE NULL END) OVER (PARTITION BY level, test) AS queue,
        MAX(CASE WHEN sequence = 0 THEN comment ELSE NULL END) OVER (PARTITION BY level, test)  AS queue_name,
        CASE
            WHEN field_1 IS NOT NULL AND operator = '.eo.' THEN CONCAT(field_1, ' = ' , field_2, ' OR ', field_1, ' = ', field_3)
            WHEN field_1 IS NOT NULL AND operator = '.no.' THEN CONCAT(field_1, ' <> ' , field_2, ' AND ', field_1, ' <> ', field_3)
            WHEN field_1 IS NOT NULL AND operator = '.os' THEN CONCAT(field_1, ' < ' , field_2, ' AND ', field_1, ' > ', field_3)
            WHEN field_1 IS NOT NULL AND operator = '.we.' THEN CONCAT(field_1, ' >= ' , field_2, ' AND ', field_1, ' <= ', field_3)
            WHEN field_1 IS NOT NULL THEN CONCAT(field_1, ' ', operator , ' ', field_2)
        END AS params
    FROM union_sources
    WHERE group = 1 and level != -1
)
SELECT
  level,
  test,
  label_number,
  queue_type,
  level_name,
  queue,
  queue_name,
  CONCAT_WS(' AND ', COLLECT_LIST(params)) AS params,
  NOW() AS ts_load
FROM calculate
WHERE params IS NOT NULL
GROUP BY 1,2,3,4,5,6,7
