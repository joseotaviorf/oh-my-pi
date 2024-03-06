SELECT
    id,
    lead_id AS id_lead,
    responsible AS id_responsible,
    distributor AS id_distributor,
    version,
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
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
