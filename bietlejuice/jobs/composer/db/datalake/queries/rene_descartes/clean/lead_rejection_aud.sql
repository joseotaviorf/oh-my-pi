SELECT
    id,
    house_lead_id AS id_house_lead,
    business_context,
    reason,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    created_at AS ts_created,
    updated_at AS ts_updated
FROM
    datalake_rene_descartes_raw.lead_rejection_aud