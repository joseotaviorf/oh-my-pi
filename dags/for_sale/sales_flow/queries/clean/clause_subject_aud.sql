SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    description,
    description_mod AS mod_description,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.clause_subject_aud
