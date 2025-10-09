WITH unpivot_table AS (
    SELECT
        id_contract_external AS id_contract,
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
    FROM datalake_cyber.contracts
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
    QUALIFY ROW_NUMBER() OVER(PARTITION BY id_contract, queue_type, dt_updated ORDER BY ts_last_activity DESC) = 1
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
