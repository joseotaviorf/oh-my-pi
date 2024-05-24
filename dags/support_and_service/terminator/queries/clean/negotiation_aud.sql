SELECT
    id,
    termination_id AS id_termination,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    needs_repair_by_tenant,
    repair_resolution,
    repair_cost,
    has_landlord_comment,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_terminator_raw.negotiation_aud
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')