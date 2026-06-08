SELECT
    id AS id_bill_action,
    bill_id AS id_bill,
    notification_entity_id AS id_notification_entity,
    action_type,
    notification_entity_name,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rental_management_raw.bill_actions
