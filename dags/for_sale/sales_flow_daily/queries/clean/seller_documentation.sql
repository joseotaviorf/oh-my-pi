SELECT
    id,
    house_id AS id_house,
    started_at AS ts_started,
    submitted_at AS ts_submitted,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.seller_documentation

