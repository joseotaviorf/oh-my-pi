SELECT
    id,
    lead_id AS id_lead,
    uuid,
    credit_value,
    installment_value,
    reduced_installment_value,
    cashback_percentage,
    cashback_value,
    target_credit_value,
    target_installment_value,
    deadline_term,
    sale_plan_contemplation,
    simulation_image_url,
    source,
    is_composed,
    expiration_date AS dt_expiration,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_consorcio_raw.simulation
