SELECT
    id,
    person_sale_id AS id_person_sale,
    event,
    amount,
    status AS outcome_status,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_monopoly_raw.outcome