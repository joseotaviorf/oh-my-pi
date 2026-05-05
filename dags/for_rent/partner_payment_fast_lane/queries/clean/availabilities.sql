SELECT
    id,
    agent_id AS id_agent,
    user_id AS id_user,
    person_uuid AS uuid_person,
    company_uuid AS uuid_company,
    bill_id AS id_bill,
    agent_type,
    amount,
    currency,
    version,
    start_date AS dt_start,
    end_date AS dt_end,
    total_working_days,
    absence_days,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.availabilities