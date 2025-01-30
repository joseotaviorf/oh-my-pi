SELECT
    id AS id_brokerage_aud,
    sales_flow_id AS id_sales_flow,
    brokerage_fee_payer,
    quinto_andar_brokerage_split,
    brokerage_fee,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id_mod AS mod_id_sales_flow,
    brokerage_fee_payer_mod AS mod_brokerage_fee_payer,
    quinto_andar_brokerage_split_mod AS mod_quinto_andar_brokerage_split,
    brokerage_fee_mod AS mod_brokerage_fee,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.brokerage_aud