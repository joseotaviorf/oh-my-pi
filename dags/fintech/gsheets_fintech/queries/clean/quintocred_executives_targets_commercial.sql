SELECT
    NULLIF(group, '') AS group,
    NULLIF(team, '') AS team,
    NULLIF(executive, '') AS executive,
    CAST(NULLIF(brokers_wes, '') AS FLOAT) AS brokers_wes,
    CAST(NULLIF(target_contatos, '') AS FLOAT) AS target_contatos,
    CAST(NULLIF(target_evaluation_started, '') AS FLOAT) AS target_evaluation_started,
    CAST(NULLIF(target_credit_approved, '') AS FLOAT) AS target_credit_approved,
    CAST(NULLIF(target_new_contract, '') AS FLOAT) AS target_new_contract,
    CAST(NULLIF(effective_contacts, '') AS FLOAT) AS effective_contacts,
    CAST(NULLIF(registrations, '') AS FLOAT) AS registrations,
    CAST(NULLIF(activations, '') AS FLOAT) AS activations,
    CAST(NULLIF(calls, '') AS FLOAT) AS calls,
    NULLIF(online_time, '') AS online_time,
    CAST(NULLIF(appointments, '') AS FLOAT) AS appointments,
    CAST(NULLIF(opportunities, '') AS FLOAT) AS opportunities,
    NULLIF(month_trunc, '') AS month_trunc,
    NULLIF(month, '') AS month,
    NULLIF(year, '') AS year
FROM
    datalake_gsheets_raw.quintocred_executives_targets_commercial
