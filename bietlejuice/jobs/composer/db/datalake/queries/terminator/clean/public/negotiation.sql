SELECT
    id,
    termination_id AS id_termination,
    has_landlord_comment,
    needs_repair_by_tenant,
    repair_resolution,
    repair_cost,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM datalake_terminator_raw.negotiation
