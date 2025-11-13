SELECT
    id,
    screening_id AS id_screening,
    negotiation_id AS id_negotiation,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.screening_negotiation
