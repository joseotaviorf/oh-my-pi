WITH deduplicate_queues AS (
          SELECT
              queue,
              queue_type,
              queue_name
          FROM datalake_cyber.queue_decision_tree
          QUALIFY ROW_NUMBER() OVER(PARTITION BY queue, queue_type ORDER BY level DESC) = 1
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
          WHERE DATE(ts_distribution) >= DATE('2025-05-29') AND DATE(ts_distribution) <= DATE('2025-07-15')
      ),
      next_ts_update AS (
          SELECT
              id_contract_external,
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
          )

      SELECT
          s.id_contract_external,
          s.segmentation_queue,
          s.segementation_queue_description AS segmentation_queue_description,
          a.agreement_queue,
          a.agreement_queue_description,
          e.eviction_queue,
          e.eviction_queue_description,
          d.date AS dt_reference
      FROM
          datalake_quintoandar.aux_date AS d
      LEFT JOIN
          next_ts_update s
          ON DATE(d.`date`) >= DATE(s.ts_last_update_segmentation_queue) AND
              IF(s.ts_update_next_segmentation_queue IS NULL, DATE(d.`date`) <= CURRENT_DATE(), DATE(d.`date`) < s.ts_update_next_segmentation_queue)
      LEFT JOIN
          next_ts_update a
          ON DATE(d.`date`) >= DATE(a.ts_last_update_agreement_queue) AND
              IF(a.ts_update_next_agreement_queue IS NULL, DATE(d.`date`) <= CURRENT_DATE(), DATE(d.`date`) < a.ts_update_next_agreement_queue)
          AND s.id_contract_external = a.id_contract_external
      LEFT JOIN
          next_ts_update e
          ON DATE(d.`date`) >= DATE(e.ts_last_update_eviction_queue) AND
              IF(e.ts_update_next_eviction_queue IS NULL, DATE(d.`date`) <= CURRENT_DATE(), DATE(d.`date`) < e.ts_update_next_eviction_queue)
          AND s.id_contract_external = e.id_contract_external
      QUALIFY
          ROW_NUMBER() OVER (PARTITION BY s.id_contract_external, d.date ORDER BY s.id_contract_external, d.date DESC) = 1
