
WITH
union_sources AS (
    SELECT
        *,
        1 AS queue_number,
        'Segmentação' AS queue_type
    FROM datalake_cyber_clean.segmentation_decision_tree

    UNION ALL

    SELECT
        *,
        3 AS queue_number,
        'Acordo' AS queue_type
    FROM datalake_cyber_clean.agreement_decision_tree

    UNION ALL

    SELECT
        *,
        4 AS queue_number,
        'Canais Digitais' AS queue_type
    FROM datalake_cyber_clean.digital_channel_decision_tree

    UNION ALL

    SELECT
        *,
        5 AS queue_number,
        'Eviction' AS queue_type
    FROM datalake_cyber_clean.eviction_decision_tree

    UNION ALL

    SELECT
        *,
        6 AS queue_number,
        'Negativação' AS queue_type
    FROM datalake_cyber_clean.credit_denial_decision_tree
),
translate_field AS (
  SELECT
    group,
    level,
    test,
    queue,
    queue_number,
    queue_type,
    sequence,
    comment,
    operator,
    CASE
      WHEN UPPER(field_1) = 'U1FLGPAUSA' THEN 'Pausa cobrança'
      WHEN UPPER(field_1) = 'U1TIPOBOL' THEN 'Boletagem'
      WHEN UPPER(field_1) = 'U1IDFMAN' THEN 'Fatura mais antiga'
      WHEN UPPER(field_1) = 'U1SITEVIC' THEN 'Status Eviction'
      WHEN UPPER(field_1) = 'U1TPCOB' THEN 'Fluxo de cobrança'
      WHEN UPPER(field_1) = 'DMDAYS' THEN 'Dias de atras'
      WHEN UPPER(field_1) = 'DMACCT' THEN 'Contrato'
      WHEN UPPER(field_1) = 'DMCURBAL' THEN 'Saldo devedor'
      WHEN UPPER(field_1) = 'DMQUE' THEN 'Fila 1 (Segmentação)'
      WHEN UPPER(field_1) = 'DMSTATE' THEN 'Estado'
      ELSE UPPER(field_1)
    END AS field,
    CONCAT("'", UPPER(field_2), "'") AS value,
    CONCAT("'", UPPER(field_3), "'") AS value_2
  FROM union_sources
),
calculate AS (
    SELECT
        group,
        level,
        test,
        queue_number,
        queue_type,
        MAX(CASE WHEN test = 0 AND sequence = -1 THEN comment ELSE NULL END) OVER (PARTITION BY level) AS level_name,
        MAX(CASE WHEN sequence = 1001 THEN queue ELSE NULL END) OVER (PARTITION BY level, test) AS queue,
        MAX(CASE WHEN sequence = 0 THEN comment ELSE NULL END) OVER (PARTITION BY level, test)  AS queue_name,
        CASE
            WHEN field IS NOT NULL AND operator = '.eo.' THEN CONCAT(field, ' = ' , value, ' OR ', field, ' = ', value_2)
            WHEN field IS NOT NULL AND operator = '.no.' THEN CONCAT(field, ' <> ' , value, ' AND ', field, ' <> ', value_2)
            WHEN field IS NOT NULL AND operator = '.os' THEN CONCAT(field, ' < ' , value, ' AND ', field, ' > ', value_2)
            WHEN field IS NOT NULL AND operator = '.we.' THEN CONCAT(field, ' >= ' , value, ' AND ', field, ' <= ', value_2)
            WHEN field IS NOT NULL THEN CONCAT(field, ' ', operator , ' ', value)
        END AS params
    FROM translate_field
    WHERE group = 1 and level != -1
)
SELECT
  level,
  test,
  queue_number,
  queue_type,
  level_name,
  queue,
  queue_name,
  CONCAT_WS(' AND ', COLLECT_LIST(params)) AS params,
  NOW() AS ts_load
FROM calculate
WHERE params IS NOT NULL
GROUP BY 1,2,3,4,5,6,7
