SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    type AS id_business_type,
    status AS id_propose_status,
    realestate AS id_real_estate,
    company_plan AS id_company_plan,
    activator AS id_activator,
    realtor,
    `hash`,
    externalref AS external_ref,
    agent_split_fee,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.propose
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
