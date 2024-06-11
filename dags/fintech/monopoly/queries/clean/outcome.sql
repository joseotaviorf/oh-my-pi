SELECT
    id,
    person_sale_id AS id_person_sale,
    revenue_share_id AS id_revenue_share,
    event,
    amount,
    status AS outcome_status,
    observations,
    DATE(due_date) AS dt_due,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.outcome