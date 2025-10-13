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
                ts_last_update_agreement_queue,
                eviction_queue,
                eviction_queue_description,
                ts_last_update_eviction_queue,
                ts_last_activity
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
                dt_reference AS ts_last_update_eviction_queue,
                NULL AS ts_last_activity
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
                ts_distribution AS ts_last_update_eviction_queue,
                NULL AS ts_last_activity
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
        unpivot_table AS (
    SELECT
        id_contract_external AS id_contract,
        priority,
        queue_type,
        CASE
            WHEN queue_type = 'agreement' THEN agreement_queue
            WHEN queue_type = 'segmentation' THEN segmentation_queue
            WHEN queue_type = 'eviction' THEN eviction_queue
        END AS queue,
        CASE
            WHEN queue_type = 'agreement' THEN agreement_queue_description
            WHEN queue_type = 'segmentation' THEN segementation_queue_description
            WHEN queue_type = 'eviction' THEN eviction_queue_description
        END AS queue_description,
        dt_updated,
        ts_last_activity
    FROM base_union
    UNPIVOT
    (dt_updated FOR queue_type IN (ts_last_update_agreement_queue AS `agreement`,
                            ts_last_update_segmentation_queue AS `segmentation`,
                            ts_last_update_eviction_queue AS `eviction`
                            ))
    ORDER BY queue_type, dt_updated, ts_last_activity
),
deduplicate_records AS (
    SELECT
        *
    FROM unpivot_table
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, queue_type, dt_updated ORDER BY ts_last_activity DESC, priority) = 1
    ORDER BY dt_updated
),
range_date_explode AS (
    SELECT
        id_contract,
        queue_type,
        queue,
        queue_description,
        dt_updated,
        COALESCE(DATE_ADD(LEAD(dt_updated) OVER(PARTITION BY id_contract, queue_type ORDER BY dt_updated),-1), CURRENT_DATE) AS dt_next_update
    FROM deduplicate_records
),
create_records_for_date AS (
    SELECT
        id_contract,
        dt_reference,
        queue_type,
        queue,
        queue_description,
        dt_reference
    FROM range_date_explode
        LATERAL VIEW EXPLODE(
            SEQUENCE(dt_updated,
                    dt_next_update
                )) AS dt_reference
    ORDER BY queue_type, dt_reference
)
SELECT
    id_contract,
    dt_reference,
    agreement_queue,
    agreement_queue_description,
    eviction_queue,
    eviction_queue_description,
    segmentation_queue,
    segmentation_queue_description
FROM
    create_records_for_date
PIVOT (MAX(queue) AS queue, MAX(queue_description) AS queue_description
        FOR queue_type
        IN ('agreement' AS agreement, 'segmentation' AS segmentation, 'eviction' AS eviction))
ORDER BY dt_reference
