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
    started_at AS ts_started,
    ended_at AS ts_ended,
    end_prevision_at AS ts_prevision_ended,
    seller_paid_at AS ts_seller_paid,
    buyer_received_keys_at AS ts_buyer_received_keys,
    kit_sent_at AS ts_kit_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.notary
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}