WITH deduped AS (
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
        day,
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
    FROM
        datalake_hub_services_raw.responsible
)
SELECT
    id,
    id_lead,
    id_responsible,
    id_distributor,
    version,
    is_active,
    ts_assigned,
    ts_unassigned,
    ts_created,
    ts_updated,
    year,
    month,
    day,
    op_cdc,
    ts_cdc_transaction,
    ts_database_transaction
FROM
    deduped
WHERE
    rn = 1
