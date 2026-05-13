WITH deduplicate_queues AS (
    SELECT
        queue,
        queue_type,
        queue_name
    FROM
        datalake_cyber.queue_decision_tree
    QUALIFY ROW_NUMBER() OVER (PARTITION BY queue, queue_type ORDER BY level DESC) = 1
),
historical_filtered AS (
    SELECT
        h.id,
        SPLIT(h.id_contract, r'\.')[0] AS id_contract_external,
        h.id_contract,
        h.contract_group,
        h.segmentation_queue,
        h.commission_queue,
        h.agreement_queue,
        h.digital_channel_queue,
        h.eviction_queue,
        h.credit_denial_queue,
        h.olos_dialer_label,
        h.evictions_reason,
        h.campaign_label,
        h.serasa_limpa_nome_label,
        h.evictions_label,
        h.label_6,
        h.days_delayed,
        h.outstanding_balance,
        h.total_delayed_amount,
        h.dt_due_date,
        h.dt_segmentation_queue_update,
        h.dt_commission_queue_update,
        h.dt_agreement_queue_update,
        h.dt_digital_channel_queue_update,
        h.dt_eviction_queue_update,
        h.dt_credit_denial_queue_update,
        h.dt_olos_dialer_label_update,
        h.dt_evictions_reason_update,
        h.dt_campaign_label_update,
        h.dt_serasa_limpa_nome_label_update,
        h.dt_evictions_label_update,
        h.dt_not_collection_label_update,
        h.ts_record_insertion
    FROM
        datalake_cyber_clean.historical_tree_decision AS h
    WHERE
        MAKE_DATE(h.year, h.month, h.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
stacked AS (
    SELECT
        id_contract_external,
        'segmentation' AS dimension_key,
        COALESCE(dt_segmentation_queue_update, DATE(ts_record_insertion)) AS dt_from,
        CAST(segmentation_queue AS STRING) AS dim_value,
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'commission',
        COALESCE(dt_commission_queue_update, DATE(ts_record_insertion)),
        CAST(commission_queue AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'agreement',
        COALESCE(dt_agreement_queue_update, DATE(ts_record_insertion)),
        CAST(agreement_queue AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'digital_channel',
        COALESCE(dt_digital_channel_queue_update, DATE(ts_record_insertion)),
        CAST(digital_channel_queue AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'eviction',
        COALESCE(dt_eviction_queue_update, DATE(ts_record_insertion)),
        CAST(eviction_queue AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'credit_denial',
        COALESCE(dt_credit_denial_queue_update, DATE(ts_record_insertion)),
        CAST(credit_denial_queue AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'olos_dialer_label',
        COALESCE(dt_olos_dialer_label_update, DATE(ts_record_insertion)),
        CAST(olos_dialer_label AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'evictions_reason',
        COALESCE(dt_evictions_reason_update, DATE(ts_record_insertion)),
        CAST(evictions_reason AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'campaign_label',
        COALESCE(dt_campaign_label_update, DATE(ts_record_insertion)),
        CAST(campaign_label AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'serasa_limpa_nome_label',
        COALESCE(dt_serasa_limpa_nome_label_update, DATE(ts_record_insertion)),
        CAST(serasa_limpa_nome_label AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'evictions_label',
        COALESCE(dt_evictions_label_update, DATE(ts_record_insertion)),
        CAST(evictions_label AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
    UNION ALL
    SELECT
        id_contract_external,
        'label_6',
        COALESCE(dt_not_collection_label_update, DATE(ts_record_insertion)),
        CAST(label_6 AS STRING),
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        historical_filtered
),
stacked_dedup AS (
    SELECT
        id_contract_external,
        dimension_key,
        dt_from,
        dim_value,
        ts_record_insertion,
        id,
        id_contract,
        contract_group,
        days_delayed,
        outstanding_balance,
        total_delayed_amount,
        dt_due_date
    FROM
        stacked
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY id_contract_external, dimension_key, dt_from
        ORDER BY ts_record_insertion DESC, id DESC
    ) = 1
),
stacked_intervals AS (
    SELECT
        sd.id_contract_external,
        sd.dimension_key,
        sd.dt_from,
        LEAD(sd.dt_from) OVER (
            PARTITION BY sd.id_contract_external, sd.dimension_key
            ORDER BY sd.dt_from, sd.ts_record_insertion, sd.id
        ) AS dt_next,
        sd.dim_value,
        sd.ts_record_insertion,
        sd.id,
        sd.id_contract,
        sd.contract_group,
        sd.days_delayed,
        sd.outstanding_balance,
        sd.total_delayed_amount,
        sd.dt_due_date
    FROM
        stacked_dedup AS sd
),
intervals AS (
    SELECT
        si.id_contract_external,
        si.dimension_key,
        si.dt_from,
        si.dt_next,
        si.dim_value,
        si.ts_record_insertion,
        si.id,
        si.id_contract,
        si.contract_group,
        si.days_delayed,
        si.outstanding_balance,
        si.total_delayed_amount,
        si.dt_due_date,
        dq.queue_name AS dim_description
    FROM
        stacked_intervals AS si
    LEFT JOIN deduplicate_queues AS dq
        ON CAST(si.dim_value AS STRING) = CAST(dq.queue AS STRING)
        AND (
            (si.dimension_key = 'segmentation' AND dq.queue_type = 'Segmentação')
            OR (si.dimension_key = 'agreement' AND dq.queue_type = 'Acordo')
            OR (si.dimension_key = 'digital_channel' AND dq.queue_type = 'Canais Digitais')
            OR (si.dimension_key = 'eviction' AND dq.queue_type = 'Eviction')
            OR (si.dimension_key = 'credit_denial' AND dq.queue_type = 'Negativação')
            OR (si.dimension_key = 'olos_dialer_label' AND dq.queue_type = 'Discador Olos')
            OR (si.dimension_key = 'campaign_label' AND dq.queue_type = 'Campaign')
            OR (si.dimension_key = 'serasa_limpa_nome_label' AND dq.queue_type = 'Label Serasa Limpa Nome')
            OR (si.dimension_key = 'evictions_label' AND dq.queue_type = 'Label Evictions')
        )
),
calendar_dim AS (
    SELECT
        i.id_contract_external,
        i.dimension_key,
        i.dim_value,
        i.dim_description,
        i.ts_record_insertion,
        i.id,
        i.id_contract,
        i.contract_group,
        i.days_delayed,
        i.outstanding_balance,
        i.total_delayed_amount,
        i.dt_due_date,
        d.date AS aux_date
    FROM
        datalake_quintoandar.aux_date AS d
    INNER JOIN intervals AS i
        ON DATE(d.date) >= i.dt_from
        AND IF(
            i.dt_next IS NULL,
            DATE(d.date) <= CURRENT_DATE(),
            DATE(d.date) < i.dt_next
        )
    WHERE
        DATE(d.date) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    cd.id_contract_external,
    MAX(cd.id) AS id,
    MAX(cd.id_contract) AS id_contract,
    MAX(cd.contract_group) AS contract_group,
    MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.dim_value END) AS segmentation_queue,
    MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.dim_description END) AS segmentation_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'commission' THEN cd.dim_value END) AS commission_queue,
    CAST(NULL AS STRING) AS commission_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.dim_value END) AS agreement_queue,
    MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.dim_description END) AS agreement_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'digital_channel' THEN cd.dim_value END) AS digital_channel_queue,
    MAX(CASE WHEN cd.dimension_key = 'digital_channel' THEN cd.dim_description END) AS digital_channel_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'eviction' THEN cd.dim_value END) AS eviction_queue,
    MAX(CASE WHEN cd.dimension_key = 'eviction' THEN cd.dim_description END) AS eviction_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'credit_denial' THEN cd.dim_value END) AS credit_denial_queue,
    MAX(CASE WHEN cd.dimension_key = 'credit_denial' THEN cd.dim_description END) AS credit_denial_queue_description,
    MAX(CASE WHEN cd.dimension_key = 'olos_dialer_label' THEN cd.dim_value END) AS olos_dialer_label,
    MAX(CASE WHEN cd.dimension_key = 'olos_dialer_label' THEN cd.dim_description END) AS olos_dialer_label_description,
    MAX(CASE WHEN cd.dimension_key = 'evictions_reason' THEN cd.dim_value END) AS evictions_reason,
    CAST(NULL AS STRING) AS evictions_reason_description,
    MAX(CASE WHEN cd.dimension_key = 'campaign_label' THEN cd.dim_value END) AS campaign_label,
    MAX(CASE WHEN cd.dimension_key = 'campaign_label' THEN cd.dim_description END) AS campaign_label_description,
    MAX(CASE WHEN cd.dimension_key = 'serasa_limpa_nome_label' THEN cd.dim_value END) AS serasa_limpa_nome_label,
    MAX(CASE WHEN cd.dimension_key = 'serasa_limpa_nome_label' THEN cd.dim_description END) AS serasa_limpa_nome_label_description,
    MAX(CASE WHEN cd.dimension_key = 'evictions_label' THEN cd.dim_value END) AS evictions_label,
    MAX(CASE WHEN cd.dimension_key = 'evictions_label' THEN cd.dim_description END) AS evictions_label_description,
    MAX(CASE WHEN cd.dimension_key = 'label_6' THEN cd.dim_value END) AS label_6,
    CAST(NULL AS STRING) AS label_6_description,
    COALESCE(
        MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.days_delayed END),
        MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.days_delayed END),
        MAX(cd.days_delayed)
    ) AS days_delayed,
    COALESCE(
        MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.outstanding_balance END),
        MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.outstanding_balance END),
        MAX(cd.outstanding_balance)
    ) AS outstanding_balance,
    COALESCE(
        MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.total_delayed_amount END),
        MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.total_delayed_amount END),
        MAX(cd.total_delayed_amount)
    ) AS total_delayed_amount,
    COALESCE(
        MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.dt_due_date END),
        MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.dt_due_date END),
        MAX(cd.dt_due_date)
    ) AS dt_due_date,
    DATE(cd.aux_date) AS dt_reference,
    COALESCE(
        MAX(CASE WHEN cd.dimension_key = 'segmentation' THEN cd.ts_record_insertion END),
        MAX(CASE WHEN cd.dimension_key = 'agreement' THEN cd.ts_record_insertion END),
        MAX(cd.ts_record_insertion)
    ) AS ts_record_insertion
FROM
    calendar_dim AS cd
GROUP BY
    cd.id_contract_external,
    DATE(cd.aux_date)
