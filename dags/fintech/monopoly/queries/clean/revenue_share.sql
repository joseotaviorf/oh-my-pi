SELECT
    id,
    person_sale_id AS id_person_sale,
    revision,
    CAST(amount AS DECIMAL(20,2)) AS amount,
    type,
    active,
    TIMESTAMP(created_at) AS ts_created
FROM
    datalake_monopoly_raw.revenue_share