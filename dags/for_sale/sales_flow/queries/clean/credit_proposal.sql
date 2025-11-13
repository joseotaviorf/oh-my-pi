SELECT
    id,
    sales_flow_id AS id_sales_flow,
    external_proposal_id as id_external_proposal,
    bank,
    macro_status,
    micro_status,
    is_chosen,
    last_macro_status_updated_at AS ts_last_macro_status_updated,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.credit_proposal
