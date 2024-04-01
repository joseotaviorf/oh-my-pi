SELECT
    id_invoice AS sk_invoice,
    bill_item_name,
    bill_item_cluster_name,
    bill_item_due_amount,
    dt_closing,
    NOW() AS ts_load
FROM datalake_losses.bill_items
