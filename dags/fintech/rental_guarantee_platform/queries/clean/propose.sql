SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    type AS id_business_type,
    status AS id_propose_status,
    realestate AS id_real_estate,
    company_plan AS id_company_plan,
    tenant_company AS id_tenant_company,
    activator AS activator_value,
    billing_model,
    realtor,
    `hash`,
    externalref AS external_ref,
    agent_split_fee,
    annual_value,
    monthly_value,
    total_coverage,
    active AS is_active,
    broker_begin AS ts_broker_begin,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.propose

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
