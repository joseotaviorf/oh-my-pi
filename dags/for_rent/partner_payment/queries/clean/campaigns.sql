SELECT
    id,
    agent_payment_id AS id_agent_payment,
    agent_id AS id_agent,
    version,
    description,
    amount,
    name, 
    approving_user,
    source_reference,
    agent_type,
    business_source,
    campaign_date AS dt_campaign,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_partner_payment_raw.campaigns