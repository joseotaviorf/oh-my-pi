SELECT
    id AS id_job,
    id_parent_job,
    offer_id AS id_offer,
    offer_agent_id AS id_offer_agent,
    offer_partner_id AS id_offer_partner,
    offer_sales_flow_id AS id_offer_sales_flow,
    job_type,
    job_date AS dt_job,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(started_at) AS ts_started,
    TIMESTAMP(finished_at) AS ts_finished
FROM
    datalake_nazare_raw.job
