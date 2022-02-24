SELECT
    id,
    lead_id AS id_lead,
    responsible_id AS id_responsible,
    distributor_id AS id_distributor,
    version,
    responsible_name,
    distributor_name,
    responsible_email,
    distributor_email,
    active AS is_active,
    assigned_at AS ts_assigned,
    unassigned_at AS ts_unassigned,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_hub_services_raw.responsible
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}