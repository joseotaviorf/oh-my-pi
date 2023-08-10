SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    type AS id_business_type,
    status AS id_propose_status,
    quintocred_status AS id_quintocred_status,
    velo_realestate AS id_velo_realestate,
    velo_company AS id_velo_company,
    quintocred_company AS id_quintocred_company,
    plan AS id_plan,
    activator AS activator_value,
    billing,
    realtor,
    `hash`,
    step,
    statusname AS status_name,
    externalref AS external_ref,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.fiancavelo_propose_legacy
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY dateupdate DESC) = 1
