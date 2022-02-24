SELECT
    id,
    lead_id AS id_lead,
    responsible_id AS id_responsible,
    distributor_id AS id_distributor,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    responsible_name,
    responsible_email,
    distributor_email,
    distributor_name,
    version,
    active AS is_active,
    lead_id_mod AS mod_id_lead,
    active_mod AS mod_is_active,
    distributor_id_mod AS mod_id_distributor,
    responsible_name_mod AS mod_responsible_name,
    responsible_id_mod AS mod_id_responsible,
    assigned_at_mod AS mod_ts_assigned,
    unassigned_at_mod AS mod_ts_unassigned,
    distributor_name_mod AS mod_distributor_name,
    assigned_at AS ts_assigned,
    unassigned_at AS ts_unassigned,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.responsible_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}