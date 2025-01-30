SELECT
    id AS id_notary,
    sales_flow_id AS id_sales_flow,
    specialist_id AS id_specialist,
    label,
    status,
    protocol,
    password,
    available_costs,
    paid_costs,
    seller_payment_status,
    customer_follow_up,
    started_at AS ts_started,
    ended_at AS ts_ended,
    end_prevision_at AS ts_prevision_ended,
    buyer_received_keys_at AS ts_buyer_received_keys,
    kit_sent_at AS ts_kit_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.notary