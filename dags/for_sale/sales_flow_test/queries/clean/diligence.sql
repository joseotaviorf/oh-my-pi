SELECT
    id AS id_diligence,
    sales_flow_id AS id_sales_flow,
    classification,
    step,
    partner_started_at AS ts_partner_started,
    partner_ended_at AS ts_partner_ended,
    legal_risk_started_at AS ts_legal_risk_started,
    legal_risk_ended_at AS ts_legal_risk_ended,
    buyer_seller_ended_at AS ts_buyer_seller_ended,
    buyer_sent_at AS ts_buyer_sent,
    seller_sent_at AS ts_seller_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.diligence
