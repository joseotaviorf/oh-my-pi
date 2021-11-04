SELECT
    CAST(id_short_house AS BIGINT) AS id_short_house,
    CAST(id_doorman AS BIGINT) AS id_doorman,
    address,
    status_crm,
    name_doorman,
    reason,
    lead_address,
    obs,
    owner_name,
    owner_phone,
    wage,
    motive,
    status,
    phone,
    dt_creation,
    dt_referral,
    dt_last_iteration
FROM
  datalake_gsheets_raw.legacy_doorman