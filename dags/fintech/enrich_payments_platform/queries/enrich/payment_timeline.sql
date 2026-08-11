WITH subscription_invoices AS (
    SELECT
        i.id,
        i.id_charge,
        i.id_subscription,
        isi.id_subscription_item,
        si.code AS id_finance_entity,
        si.ts_created
    FROM
        datalake_wall_street_clean.invoice i
    LEFT JOIN
        datalake_wall_street_clean.invoice_subscription_item isi
        ON isi.id_invoice = i.id
    LEFT JOIN
        datalake_wall_street_clean.subscription_item si
        ON si.id = isi.id_subscription_item
    LEFT JOIN
        datalake_wall_street_clean.subscription AS s
        ON si.code  = (s.code || '|default-item')
    LEFT JOIN
        datalake_wall_street_clean.subscription AS s1
        ON si.code  = (s1.code || '_item')
    WHERE
        s.code IS NULL
        AND s1.code IS NULL
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY i.id_charge ORDER BY si.ts_created DESC) = 1
),
charge_aud_timeline AS (
    SELECT
        id,
        rev,
        rev_type,
        charge_status,
        ts_updated,
        acquire_charge_status,
        acquire_auth_code,
        acquire_nsu,
        id_acquire_transaction,
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY rev) as timeline_order
    FROM
        datalake_wall_street_clean.charge_aud
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id, charge_status ORDER BY rev DESC) = 1
),
charge_status_log_timeline AS (
    SELECT
        id_charge,
        status,
        payment_method,
        ts_started_processing,
        ts_created,
        ts_paid,
        ts_canceled,
        ts_updated
    FROM
        datalake_checkout_clean.charge_status_log
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_charge, payment_method, status ORDER BY ts_updated DESC) = 1
),
charge_created AS (
    SELECT
        id,
        FIRST_VALUE(ts_updated) OVER(PARTITION BY id ORDER BY rev) AS ts_created
    FROM
        datalake_wall_street_clean.charge_aud
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY rev DESC) = 1
),
charge_canceled AS (
    SELECT
        id,
        FIRST_VALUE(ts_updated) OVER(PARTITION BY id ORDER BY rev) AS ts_canceled
    FROM
        datalake_wall_street_clean.charge_aud
    WHERE
        charge_status = 'CANCELED'
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id ORDER BY rev DESC) = 1
),
unique_ws_charge AS (
    SELECT
        id,
        id_finance_entity,
        acquire_tid,
        code,
        ts_paid
    FROM
        datalake_wall_street_clean.charge
    QUALIFY
        IF(COUNT(*) OVER (PARTITION BY id_finance_entity) > 1, acquire_tid <> '-1', TRUE)
        AND IF(acquire_tid <> '-1', ROW_NUMBER() OVER (PARTITION BY id_finance_entity ORDER BY IF(acquire_tid <> '-1', 0, 1), ts_paid) = 1, FALSE)
),
ws_charge AS (
    SELECT
        c.id,
        c.id_finance_entity,
        c.code,
        cat.charge_status AS charge_status_timeline,
        cat.ts_updated AS ts_updated_timeline,
        cat.timeline_order
    FROM
        unique_ws_charge c
    LEFT JOIN
        charge_aud_timeline cat
        ON cat.id = c.id
),
unique_credit_card_payments AS (
    SELECT
        cc.id_charge AS id_checkout_charge,
        wsc.id AS id_ws_charge,
        COALESCE(cc.id_finance_entity, wsc.id_finance_entity, si.id_finance_entity) AS id_finance_entity
    FROM
        datalake_checkout_clean.credit_card AS cc
    LEFT JOIN
        datalake_checkout_clean.credit_card_capture_attempt AS cca
        ON cca.id_credit_card = cc.id
    FULL JOIN
        ws_charge AS wsc
        ON  wsc.code = cca.code
        AND wsc.id_finance_entity = cc.id_finance_entity
    LEFT JOIN
        subscription_invoices AS si
        ON si.id_charge = wsc.id
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY COALESCE(cc.id_finance_entity, si.id_finance_entity, wsc.id_finance_entity), COALESCE(cc.id_charge, wsc.id) ORDER BY COALESCE(cca.ts_created, wsc.ts_updated_timeline, cc.ts_created) DESC) = 1
),
credit_card_payments AS (
    SELECT
        uccp.*,
        csl.charge_status AS status_timeline,
        csl.ts_updated AS ts_updated_timeline,
        csl.timeline_order
    FROM
        unique_credit_card_payments uccp
    LEFT JOIN
        charge_aud_timeline csl
        ON csl.id = uccp.id_ws_charge
),
unique_checkout AS (
    SELECT
        ch.id AS id_charge,
        IF(o.status = 'PAID',ch.payment_method, NULL) AS successfull_method,
        'checkout' AS datasource,
        o.id_finance_entity
    FROM
        datalake_checkout_clean.order AS o
    LEFT JOIN
        datalake_checkout_clean.charge AS ch
        ON ch.id_order = o.id
    WHERE
        ch.id IS NOT NULL
),
checkout AS (
    SELECT
        uc.*,
        csl.status AS status_timeline,
        csl.payment_method AS payment_method_timeline,
        csl.ts_updated AS ts_updated_timeline,
        uc.id_finance_entity,
        ROW_NUMBER() OVER(PARTITION BY csl.id_charge ORDER BY csl.ts_updated) as timeline_order
    FROM
        unique_checkout uc
    LEFT JOIN
        charge_status_log_timeline csl
        ON csl.id_charge = uc.id_charge
),
vans_boleto AS (
    SELECT
        b.id AS id_charge,
        b.status AS status_timeline, -- TODO: bring real timeline status evolution in the future
        'BOLETO' AS payment_method_timeline,
        'vans' AS datasource,
        b.id_bank_boleto AS id_finance_entity,
        NULL as ts_updated_timeline,
        NULL as timeline_order
    FROM
        datalake_vans_clean.boleto b
    LEFT JOIN
        datalake_vans_clean.boleto_file bf
        ON b.id = bf.id_boleto
    LEFT JOIN
        datalake_vans_clean.file f
        ON f.id = bf.id_file
    WHERE
        b.status IS NOT NULL
        AND b.requested_by = 'seubarriga'
        AND b.id_related_document IS NOT NULL
        AND b.related_document_type = 'invoice'
        AND f.type = ':file.type/boleto'
),
cte_union AS (
    SELECT
        CONCAT(COALESCE(id_ws_charge, id_checkout_charge), '_wallstreet') AS id_business_key,
        id_checkout_charge AS id_charge,
        'wallstreet' AS datasource,
        status_timeline as timeline_status,
        'CREDIT_CARD' AS payment_method_timeline,
        ts_updated_timeline as timeline_timestamp,
        timeline_order,
        id_finance_entity
    FROM
        credit_card_payments
    WHERE
        id_checkout_charge IS NULL

    UNION ALL

    SELECT
        CONCAT(COALESCE(id_charge, ''), '_', datasource) AS id_business_key,
        id_charge,
        datasource,
        status_timeline as timeline_status,
        payment_method_timeline,
        ts_updated_timeline as timeline_timestamp,
        timeline_order,
        id_finance_entity
    FROM
        checkout
    WHERE
        id_charge IS NOT NULL

    UNION ALL

    SELECT
        CONCAT(COALESCE(id_charge, ''), '_', datasource) AS id_business_key,
        id_charge,
        datasource,
        status_timeline as timeline_status,
        payment_method_timeline,
        ts_updated_timeline as timeline_timestamp,
        timeline_order,
        id_finance_entity
    FROM
        vans_boleto
)
SELECT DISTINCT
    -- id_payment_timeline BIGINT GENERATED ALWAYS AS IDENTITY (created directly on Databricks CREATE TABLE)
    id_business_key,
    datasource,
    CASE
        WHEN timeline_status = '' THEN NULL
        WHEN timeline_status = '52' THEN NULL
        WHEN timeline_status = 'PAID' THEN 'PAID'
        WHEN timeline_status = 'PROCESSING' THEN 'PROCESSING'
        WHEN timeline_status = 'ERROR' THEN 'ERROR'
        WHEN timeline_status = 'CANCELED' THEN 'CANCELED'
        WHEN timeline_status = 'CHARGEBACK' THEN 'CHARGEBACK'
        WHEN timeline_status = 'CHARGEBACK_CAPTURED' THEN 'CHARGEBACK_CAPTURED'
        WHEN timeline_status = 'REFUNDED' THEN 'REFUNDED'
        WHEN timeline_status = 'PROCESSING_REFUND' THEN 'PROCESSING_REFUND'
        WHEN timeline_status = 'PENDING_CAPTURE' THEN 'PENDING_CAPTURE'
        WHEN timeline_status = 'CAPTURE_NOT_PROCESSED' THEN 'CAPTURE_NOT_PROCESSED'
        WHEN timeline_status = 'CAPTURE_DENIED' THEN 'CAPTURE_DENIED'
        WHEN timeline_status = 'CAPTURE_BLOCKED' THEN 'CAPTURE_BLOCKED'
        WHEN timeline_status = 'CAPTURED' THEN 'CAPTURED'
        WHEN timeline_status = 'PENDING_CANCELATION' THEN 'PENDING_CANCELATION'
        WHEN timeline_status = 'CANCELATION_NOT_PROCESSED' THEN 'CANCELATION_NOT_PROCESSED'
        WHEN timeline_status = 'OPEN' THEN 'OPEN'
        WHEN timeline_status = 'REQUESTED' THEN 'REQUESTED'
        WHEN timeline_status = 'PENDING_REGISTER_PAYMENT' THEN 'PENDING_REGISTER_PAYMENT'
        WHEN timeline_status = ':boleto.status/paid' THEN 'PAID'
        WHEN timeline_status = ':boleto.status/scheduled' THEN 'SCHEDULED'
        WHEN timeline_status = ':boleto.status/processed' THEN 'PROCESSED'
        WHEN timeline_status = ':boleto.status/error' THEN 'ERROR'
        WHEN timeline_status = ':boleto.status/chargeback' THEN 'CHARGEBACK'
        WHEN timeline_status = ':boleto.status/requested' THEN 'REQUESTED'
        WHEN timeline_status = ':boleto.status/canceled' THEN 'CANCELED'
        WHEN timeline_status = ':boleto.status/write-down-requested' THEN 'PENDING_WRITE_DOWN'
        WHEN timeline_status = ':boleto.status/created' THEN 'CREATED'
        WHEN timeline_status = ':boleto.status/written-down' THEN 'WRITTEN_DOWN'
        WHEN timeline_status = ':boleto.status/written-down-error' THEN 'WRITE_DOWN_ERROR'
        WHEN timeline_status = ':boleto.status/write-down-paid-requested' THEN 'PENDING_WRITE_DOWN_PAID'
        WHEN timeline_status = ':boleto.status/changed' THEN 'CHANGED'
        ELSE timeline_status
    END AS timeline_status,
    payment_method_timeline,
    timeline_order,
    id_finance_entity,
    timeline_timestamp
FROM
    cte_union
