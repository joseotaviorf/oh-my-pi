WITH deduplicate_queues AS (
  SELECT
    queue,
    queue_type,
    queue_name
  FROM (
    SELECT
      queue,
      queue_type,
      queue_name,
      ROW_NUMBER() OVER (PARTITION BY queue, queue_type ORDER BY level DESC) AS _w,
      level
    FROM datalake_cyber.queue_decision_tree
  ) AS _t
  WHERE
    _w = 1
), base_union AS (
  SELECT
    id_contract_external,
    1 AS priority,
    segmentation_queue,
    segementation_queue_description,
    ts_last_update_segmentation_queue,
    agreement_queue,
    agreement_queue_description,
    IF(
      ROW_NUMBER() OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue, ts_last_update_segmentation_queue) = 1
      AND ts_last_update_agreement_queue > ts_last_update_segmentation_queue,
      ts_last_update_segmentation_queue,
      ts_last_update_agreement_queue
    ) AS ts_last_update_agreement_queue,
    eviction_queue,
    eviction_queue_description,
    ts_last_update_eviction_queue
  FROM datalake_cyber.contracts
  UNION ALL
  SELECT
    SPLIT(id_contract, '\\.')[0] AS id_contract_external,
    2 AS priority,
    segmentation_queue,
    qdts.queue_name AS segementation_queue_description,
    dt_reference AS ts_last_update_segmentation_queue,
    agreement_queue,
    qdta.queue_name AS agreement_queue_description,
    dt_reference AS ts_last_update_agreement_queue,
    eviction_queue,
    qdte.queue_name AS eviction_queue_description,
    dt_reference AS ts_last_update_eviction_queue
  FROM datalake_cyber.fallback_queue AS fq
  LEFT JOIN deduplicate_queues AS qdta
    ON fq.agreement_queue = qdta.queue AND qdta.queue_type = 'Acordo'
  LEFT JOIN deduplicate_queues AS qdts
    ON fq.segmentation_queue = qdts.queue AND qdts.queue_type = 'Segmentação'
  LEFT JOIN deduplicate_queues AS qdte
    ON fq.eviction_queue = qdte.queue AND qdte.queue_type = 'Eviction'
  WHERE
    dt_reference >= CAST('2025-05-29' AS DATE)
    AND dt_reference <= CAST('2025-07-15' AS DATE)
  UNION ALL
  SELECT
    SPLIT(id_contract, '\\.')[0] AS id_contract_external,
    3 AS priority,
    segmentation_queue,
    qdts.queue_name AS segementation_queue_description,
    ts_distribution AS ts_last_update_segmentation_queue,
    agreement_queue,
    qdta.queue_name AS agreement_queue_description,
    ts_distribution AS ts_last_update_agreement_queue,
    eviction_queue,
    qdte.queue_name AS eviction_queue_description,
    ts_distribution AS ts_last_update_eviction_queue
  FROM datalake_cyber_clean.history_contract_distribution AS h
  LEFT JOIN deduplicate_queues AS qdta
    ON h.agreement_queue = qdta.queue AND qdta.queue_type = 'Acordo'
  LEFT JOIN deduplicate_queues AS qdts
    ON h.segmentation_queue = qdts.queue AND qdts.queue_type = 'Segmentação'
  LEFT JOIN deduplicate_queues AS qdte
    ON h.eviction_queue = qdte.queue AND qdte.queue_type = 'Eviction'
), next_ts_update AS (
  SELECT
    id_contract_external,
    segmentation_queue,
    segementation_queue_description,
    ts_last_update_segmentation_queue,
    LEAD(ts_last_update_segmentation_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_segmentation_queue, priority) AS ts_update_next_segmentation_queue,
    agreement_queue,
    agreement_queue_description,
    IF(
      ROW_NUMBER() OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue, priority, ts_last_update_segmentation_queue) = 1
      AND ts_last_update_agreement_queue > ts_last_update_segmentation_queue,
      ts_last_update_segmentation_queue,
      ts_last_update_agreement_queue
    ) AS ts_last_update_agreement_queue,
    LEAD(ts_last_update_agreement_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue) AS ts_update_next_agreement_queue,
    eviction_queue,
    eviction_queue_description,
    ts_last_update_eviction_queue,
    LEAD(ts_last_update_eviction_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_eviction_queue, priority) AS ts_update_next_eviction_queue
  FROM base_union
)
SELECT
  id_contract_external,
  segmentation_queue,
  segmentation_queue_description,
  agreement_queue,
  agreement_queue_description,
  eviction_queue,
  eviction_queue_description,
  dt_reference
FROM (
  SELECT
    s.id_contract_external,
    s.segmentation_queue,
    s.segementation_queue_description AS segmentation_queue_description,
    a.agreement_queue,
    a.agreement_queue_description,
    e.eviction_queue,
    e.eviction_queue_description,
    d.date AS dt_reference,
    ROW_NUMBER() OVER (PARTITION BY s.id_contract_external, d.date ORDER BY s.id_contract_external, d.date DESC) AS _w,
    d.date
  FROM datalake_quintoandar.aux_date AS d
  LEFT JOIN next_ts_update AS s
    ON CAST(d.`date` AS DATE) >= CAST(s.ts_last_update_segmentation_queue AS DATE)
    AND IF(
      s.ts_update_next_segmentation_queue IS NULL,
      CAST(d.`date` AS DATE) <= CURRENT_DATE,
      CAST(d.`date` AS DATE) < s.ts_update_next_segmentation_queue
    )
  LEFT JOIN next_ts_update AS a
    ON CAST(d.`date` AS DATE) >= CAST(a.ts_last_update_agreement_queue AS DATE)
    AND IF(
      a.ts_update_next_agreement_queue IS NULL,
      CAST(d.`date` AS DATE) <= CURRENT_DATE,
      CAST(d.`date` AS DATE) < a.ts_update_next_agreement_queue
    )
    AND s.id_contract_external = a.id_contract_external
  LEFT JOIN next_ts_update AS e
    ON CAST(d.`date` AS DATE) >= CAST(e.ts_last_update_eviction_queue AS DATE)
    AND IF(
      e.ts_update_next_eviction_queue IS NULL,
      CAST(d.`date` AS DATE) <= CURRENT_DATE,
      CAST(d.`date` AS DATE) < e.ts_update_next_eviction_queue
    )
    AND s.id_contract_external = e.id_contract_external
) AS _t
WHERE
  _w = 1
