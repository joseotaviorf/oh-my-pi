SELECT
    rae_id AS id_rae,
    full_columns_name,
    exception_type,
    contains_pii as has_pii,
    data_subject_type,
    requester,
    justification,
    comments,
    status,
    lgpd_impact,
    focal_points,
    approved_by,
    to_date(date_of_activation, "dd/MM/yyyy") as dt_activation,
    to_date(approval_date, "dd/MM/yyyy") as dt_approval,
    to_date(last_review, "dd/MM/yyyy") as dt_last_reviewed
    pull_request
FROM
    datalake_gsheets_raw.anonymization_pii_rae
