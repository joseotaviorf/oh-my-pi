SELECT
    id,
    sales_flow_id AS id_sales_flow,
    use_fgts AS has_fgts_draft,
    has_final_value_refund,
    is_seller_pj,
    is_buyer_pj,
    buyer_documentation_started_at AS ts_buyer_documentation_started,
    buyer_documentation_submitted_at AS ts_buyer_documentation_submitted,
    seller_documentation_started_at AS ts_seller_documentation_started,
    seller_documentation_submitted_at AS ts_seller_documentation_submitted,
    buyer_credit_started_at AS ts_buyer_credit_started,
    buyer_credit_submitted_at AS ts_buyer_credit_submitted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_sales_flow_raw.negotiation
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
