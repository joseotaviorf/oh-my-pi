SELECT 
    id,
    external_id AS id_external,
    business_entity_id AS id_business_entity,
    finance_entity_id AS id_finance_entity,
    tracking_id AS id_tracking,
    requester_id AS id_requester,
    due_amount,
    paid_amount,
    discount,
    status,
    requester_name,
    TIMESTAMP(started_processing_at) AS ts_started_processing,
    TIMESTAMP(created_at) AS ts_created,
    DATE(due_date) AS dt_due,
    TIMESTAMP(paid_at) AS ts_paid,
    TIMESTAMP(canceled_at) AS ts_canceled,
    TIMESTAMP(deleted_at) AS ts_deleted,
    TIMESTAMP(updated_at) AS ts_updated
FROM 
    datalake_checkout_homolog_raw.order