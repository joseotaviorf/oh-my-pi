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
      ROW_NUMBER() OVER(PARTITION BY queue, queue_type ORDER BY level DESC) AS rn
    FROM datalake_cyber.queue_decision_tree
  )
  WHERE rn = 1
),
base_union AS (
  SELECT
    id_contract_external,
    1 AS priority,
    segmentation_queue,
    segementation_queue_description,
    ts_last_update_segmentation_queue,
    agreement_queue,
    agreement_queue_description,
    IF(ROW_NUMBER() OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue, ts_last_update_segmentation_queue) = 1 AND ts_last_update_agreement_queue > ts_last_update_segmentation_queue, ts_last_update_segmentation_queue, ts_last_update_agreement_queue) AS ts_last_update_agreement_queue,
    eviction_queue,
    eviction_queue_description,
    ts_last_update_eviction_queue
  FROM
    datalake_cyber.contracts

  UNION ALL

  SELECT
    SPLIT(id_contract,r'\.')[0] AS id_contract_external,
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
  FROM
    datalake_cyber.fallback_queue fq
  LEFT JOIN deduplicate_queues AS qdta
    ON fq.agreement_queue = qdta.queue AND qdta.queue_type = 'Acordo'
  LEFT JOIN deduplicate_queues AS qdts
    ON fq.segmentation_queue = qdts.queue AND qdts.queue_type = 'Segmentação'
  LEFT JOIN deduplicate_queues AS qdte
    ON fq.eviction_queue = qdte.queue AND qdte.queue_type = 'Eviction'
  WHERE dt_reference >= DATE('2025-05-29') AND dt_reference <= DATE('2025-07-15')

  UNION ALL

  SELECT
    SPLIT(id_contract,r'\.')[0] AS id_contract_external,
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
  FROM
    datalake_cyber_clean.history_contract_distribution h
  LEFT JOIN deduplicate_queues AS qdta
    ON h.agreement_queue = qdta.queue AND qdta.queue_type = 'Acordo'
  LEFT JOIN deduplicate_queues AS qdts
    ON h.segmentation_queue = qdts.queue AND qdts.queue_type = 'Segmentação'
  LEFT JOIN deduplicate_queues AS qdte
    ON h.eviction_queue = qdte.queue AND qdte.queue_type = 'Eviction'
),
next_ts_update AS (
  SELECT
    id_contract_external,
    priority,
    segmentation_queue,
    segementation_queue_description,
    ts_last_update_segmentation_queue,
    LEAD(ts_last_update_segmentation_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_segmentation_queue, priority) AS ts_update_next_segmentation_queue,
    agreement_queue,
    agreement_queue_description,
    IF(ROW_NUMBER() OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue, priority, ts_last_update_segmentation_queue) = 1 AND ts_last_update_agreement_queue > ts_last_update_segmentation_queue, ts_last_update_segmentation_queue, ts_last_update_agreement_queue) AS ts_last_update_agreement_queue,
    LEAD(ts_last_update_agreement_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_agreement_queue) AS ts_update_next_agreement_queue,
    eviction_queue,
    eviction_queue_description,
    ts_last_update_eviction_queue,
    LEAD(ts_last_update_eviction_queue) OVER (PARTITION BY id_contract_external ORDER BY ts_last_update_eviction_queue, priority) AS ts_update_next_eviction_queue
  FROM
    base_union
),
-- The calendar bounds clamp each validity interval to the dates that actually exist in
-- `aux_date`. The previous range join did this implicitly (it was driven by `aux_date`);
-- clamping here keeps SEQUENCE from materialising decades of dates for sentinel timestamps.
calendar_bounds AS (
  SELECT
    MIN(DATE(`date`)) AS dt_calendar_from,
    MAX(DATE(`date`)) AS dt_calendar_to
  FROM datalake_quintoandar.aux_date
),
-- Each queue dimension is turned from a validity *interval* into one row per day, so the
-- timeline can be assembled with equi-joins.
--
-- `dt_valid_to` reproduces the original predicate exactly:
--   IF(ts_next IS NULL, d.date <= CURRENT_DATE(), d.date < ts_next)
-- `d.date < ts_next` compares a DATE (midnight) against a TIMESTAMP, so the last included
-- day is DATE(ts_next) - 1 when ts_next falls exactly on midnight, and DATE(ts_next)
-- otherwise.
segmentation_intervals AS (
  SELECT
    n.id_contract_external,
    n.priority,
    n.segmentation_queue,
    n.segementation_queue_description AS segmentation_queue_description,
    GREATEST(DATE(n.ts_last_update_segmentation_queue), (SELECT dt_calendar_from FROM calendar_bounds)) AS dt_valid_from,
    LEAST(
      IF(
        n.ts_update_next_segmentation_queue IS NULL,
        CURRENT_DATE(),
        IF(
          n.ts_update_next_segmentation_queue = DATE_TRUNC('DAY', n.ts_update_next_segmentation_queue),
          DATE_ADD(DATE(n.ts_update_next_segmentation_queue), -1),
          DATE(n.ts_update_next_segmentation_queue)
        )
      ),
      (SELECT dt_calendar_to FROM calendar_bounds)
    ) AS dt_valid_to
  FROM next_ts_update AS n
  WHERE n.ts_last_update_segmentation_queue IS NOT NULL
),
segmentation_daily AS (
  SELECT
    id_contract_external,
    priority,
    segmentation_queue,
    segmentation_queue_description,
    EXPLODE(SEQUENCE(dt_valid_from, dt_valid_to, INTERVAL 1 DAY)) AS dt_reference
  FROM segmentation_intervals
  WHERE dt_valid_from <= dt_valid_to
),
agreement_intervals AS (
  SELECT
    n.id_contract_external,
    n.priority,
    n.agreement_queue,
    n.agreement_queue_description,
    GREATEST(DATE(n.ts_last_update_agreement_queue), (SELECT dt_calendar_from FROM calendar_bounds)) AS dt_valid_from,
    LEAST(
      IF(
        n.ts_update_next_agreement_queue IS NULL,
        CURRENT_DATE(),
        IF(
          n.ts_update_next_agreement_queue = DATE_TRUNC('DAY', n.ts_update_next_agreement_queue),
          DATE_ADD(DATE(n.ts_update_next_agreement_queue), -1),
          DATE(n.ts_update_next_agreement_queue)
        )
      ),
      (SELECT dt_calendar_to FROM calendar_bounds)
    ) AS dt_valid_to
  FROM next_ts_update AS n
  WHERE n.ts_last_update_agreement_queue IS NOT NULL
),
agreement_daily AS (
  SELECT
    id_contract_external,
    priority,
    agreement_queue,
    agreement_queue_description,
    EXPLODE(SEQUENCE(dt_valid_from, dt_valid_to, INTERVAL 1 DAY)) AS dt_reference
  FROM agreement_intervals
  WHERE dt_valid_from <= dt_valid_to
),
eviction_intervals AS (
  SELECT
    n.id_contract_external,
    n.priority,
    n.eviction_queue,
    n.eviction_queue_description,
    GREATEST(DATE(n.ts_last_update_eviction_queue), (SELECT dt_calendar_from FROM calendar_bounds)) AS dt_valid_from,
    LEAST(
      IF(
        n.ts_update_next_eviction_queue IS NULL,
        CURRENT_DATE(),
        IF(
          n.ts_update_next_eviction_queue = DATE_TRUNC('DAY', n.ts_update_next_eviction_queue),
          DATE_ADD(DATE(n.ts_update_next_eviction_queue), -1),
          DATE(n.ts_update_next_eviction_queue)
        )
      ),
      (SELECT dt_calendar_to FROM calendar_bounds)
    ) AS dt_valid_to
  FROM next_ts_update AS n
  WHERE n.ts_last_update_eviction_queue IS NOT NULL
),
eviction_daily AS (
  SELECT
    id_contract_external,
    priority,
    eviction_queue,
    eviction_queue_description,
    EXPLODE(SEQUENCE(dt_valid_from, dt_valid_to, INTERVAL 1 DAY)) AS dt_reference
  FROM eviction_intervals
  WHERE dt_valid_from <= dt_valid_to
),
-- Assembled purely with equi-joins on (id_contract_external, dt_reference). The previous
-- version joined `aux_date` to the queue history on inequality predicates only, which
-- Spark can execute solely as a BroadcastNestedLoopJoin — on EMR that collapsed the whole
-- timeline onto a single task.
timeline_base AS (
  SELECT
    s.id_contract_external,
    s.segmentation_queue,
    s.segmentation_queue_description,
    a.agreement_queue,
    a.agreement_queue_description,
    e.eviction_queue,
    e.eviction_queue_description,
    s.dt_reference,
    ROW_NUMBER() OVER (
      PARTITION BY s.id_contract_external, s.dt_reference
      ORDER BY s.priority, a.priority, e.priority, s.segmentation_queue, a.agreement_queue, e.eviction_queue
    ) AS rn
  FROM segmentation_daily AS s
  INNER JOIN datalake_quintoandar.aux_date AS d
    ON DATE(d.`date`) = s.dt_reference
  LEFT JOIN agreement_daily AS a
    ON a.id_contract_external = s.id_contract_external
      AND a.dt_reference = s.dt_reference
  LEFT JOIN eviction_daily AS e
    ON e.id_contract_external = s.id_contract_external
      AND e.dt_reference = s.dt_reference
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
FROM timeline_base
WHERE rn = 1
