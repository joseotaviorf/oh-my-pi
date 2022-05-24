WITH macro_status AS (
    -- Returns only the macro_status, which are the lines with id_parent = null.
    SELECT
        id,
        id_label,
        id_parent,
        key
    FROM
        datalake_sales_flow_clean.status
    WHERE id_parent IS NULL
),
ordering AS (
    SELECT
        id,
        id_closing_type,
        id_status,
        ordering
    FROM
        datalake_sales_flow_clean.status_order
),
offer AS (
    SELECT
        DISTINCT
            id_sales_flow,
            id_firestore
    FROM
        datalake_sales_flow_clean.offer
),
micro_status_keys AS (
    SELECT
        id,
        id_label,
        id_parent,
        key
    FROM
        datalake_sales_flow_clean.status
    WHERE id_parent IS NOT NULL
),
micro_status AS (
    -- Returns the last micro status that had an update for each macro_status.
    WITH last_micro_status AS (
        SELECT
            sr.id_sales_flow,
            CASE
                WHEN stt.id_parent IS NULL THEN sr.id_status
                WHEN stt.id_parent IS NOT NULL THEN stt.id_parent
            END AS macro_status_id,
            CASE
                WHEN stt.id_parent IS NOT NULL THEN sr.id_status
                ELSE NULL
            END AS micro_status_id,
            sr.ts_status_start,
            sr.ts_status_end,
            sr.ts_updated
    FROM
        datalake_sales_flow_clean.status_record AS sr
    LEFT JOIN
        datalake_sales_flow_clean.status AS stt
            ON sr.id_status = stt.id
  )
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow, macro_status_id ORDER BY ts_updated DESC) AS rw_micro
    FROM last_micro_status
    WHERE
        micro_status_id IS NOT NULL
),
closing_type_keys AS (
    SELECT
        id,
        key,
        id_parent
    FROM
        datalake_sales_flow_clean.closing_type
),
sales_flow AS (
    -- Returns the last update for an offer, because it can change the id_closing_type during the time.
    SELECT
        id AS id_sales_flow,
        id_closing_type,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) AS rw,
        ts_updated
    FROM
        datalake_sales_flow_clean.sales_flow
),
closing_type AS (
    -- Returns the micro and macro status id for each offer for its last id_closing_type on table sales_flow.
    -- On table sales_flow the id_closing_type can be the micro status id, so in order to return both ids the
    -- CASE WHEN was used.
    SELECT
        sf.id AS id_sales_flow,
        CASE
            WHEN ct.id_parent IS null THEN sf.id_closing_type
            WHEN ct.id_parent IS NOT null THEN ct.id_parent
        END AS primary_ct,
        CASE
            WHEN ct.id_parent IS NOT null THEN sf.id_closing_type
            ELSE NULL
        END AS sec_ct,
        sf.ts_updated
    FROM
        datalake_sales_flow_clean.sales_flow AS sf
    LEFT JOIN
        datalake_sales_flow_clean.closing_type ct
            ON ct.id = sf.id_closing_type
),
last_closing_type AS (
    WITH last_row_number_closing_type (
        SELECT
            *,
            ROW_NUMBER() OVER (PARTITION BY id_sales_flow, primary_ct ORDER BY ts_updated DESC) AS rw_primary
        FROM closing_type
    )
    SELECT
        *
    FROM
        last_row_number_closing_type
    WHERE
        rw_primary = 1
),
offer_status AS (
    SELECT
        id,
        id_sales_flow,
        id_status,
        ts_status_start,
        ts_status_end,
        ROW_NUMBER() OVER (PARTITION BY id_sales_flow, id_status ORDER BY ts_status_end DESC) AS rw_offer_status
    FROM
        datalake_sales_flow_clean.status_record
)

SELECT
    ofs.id_sales_flow,
    off.id_firestore,
    ctk.key AS primary_closing_type_label,
    ctk_sec.key AS secundary_closing_type_label,
    ms.key AS macro_status_name,
    ord.ordering,
    ms_key.key AS last_micro_status_name,
    ofs.ts_status_start AS ts_macro_status_start,
    ofs.ts_status_end AS ts_macro_status_end,
    micro.ts_updated AS ts_micro_status_last_update
FROM
    offer_status AS ofs
LEFT JOIN
    macro_status AS ms
        ON ofs.id_status = ms.id
        AND rw_offer_status = 1
LEFT JOIN
    sales_flow AS sf
        ON ofs.id_sales_flow = sf.id_sales_flow
        AND rw = 1
LEFT JOIN
    last_closing_type AS ct
        ON ct.id_sales_flow = sf.id_sales_flow
LEFT JOIN
    closing_type_keys AS ctk
        ON ctk.id = ct.primary_ct
LEFT JOIN
    closing_type_keys AS ctk_sec
        ON ctk_sec.id = ct.sec_ct
LEFT JOIN
    micro_status AS micro
        ON micro.id_sales_flow = sf.id_sales_flow
        AND micro.macro_status_id = ms.id
        AND rw_micro = 1
LEFT JOIN
    micro_status_keys AS ms_key
        ON ms_key.id = micro.micro_status_id
LEFT JOIN
    offer AS off
        ON off.id_sales_flow = sf.id_sales_flow
LEFT JOIN
    ordering AS ord
        ON ord.id_closing_type = COALESCE(sec_ct, primary_ct)
        AND ord.id_status = ofs.id_status
WHERE
    ms.key IS NOT NULL
ORDER BY
    ordering ASC,
    sf.id_sales_flow ASC
