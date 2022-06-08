SELECT
    CAST(REGEXP_REPLACE(nps_global,'([^-0-9])','') AS INT) AS nps_global,
    CAST(REGEXP_REPLACE(nps_global_4060_l4w,'([^-0-9])','') AS INT) AS nps_global_4060_l4w,
    CAST(REGEXP_REPLACE(fr_lost,'([^-0-9])','') AS INT) AS fr_lost,
    CAST(REGEXP_REPLACE(lost_visits_fr,'([^-0-9])','') AS INT) AS lost_visits_fr,
    CAST(REGEXP_REPLACE(lost_proposals_fr,'([^-0-9])','') AS INT) AS lost_proposals_fr,
    CAST(REGEXP_REPLACE(unpublished_fr,'([^-0-9])','') AS INT) AS unpublished_fr,
    CAST(REGEXP_REPLACE(fr_true,'([^-0-9])','') AS INT) AS fr_true,
    CAST(REGEXP_REPLACE(fr_onboarding,'([^-0-9])','') AS INT) AS fr_onboarding,
    CAST(REGEXP_REPLACE(fr_ongoing,'([^-0-9])','') AS INT) AS fr_ongoing,
    CAST(REGEXP_REPLACE(fr_offboarding,'([^-0-9])','') AS INT) AS fr_offboarding,
    CAST(REGEXP_REPLACE(fr_lost_iq_rejected,'([^-0-9])','') AS INT) AS fr_lost_iq_rejected,
    CAST(REGEXP_REPLACE(fs_true,'([^-0-9])','') AS INT) AS fs_true,
    CAST(REGEXP_REPLACE(fs_lost,'([^-0-9])','') AS INT) AS fs_lost,
    CAST(REGEXP_REPLACE(fs_ccv,'([^-0-9])','') AS INT) AS fs_ccv,
    CAST(REGEXP_REPLACE(fs_registry,'([^-0-9])','') AS INT) AS fs_registry,
    CAST(REGEXP_REPLACE(unpublished_fs,'([^-0-9])','') AS INT) AS unpublished_fs,
    CAST(REGEXP_REPLACE(lost_visits_fs,'([^-0-9])','') AS INT) AS lost_visits_fs,
    CAST(REGEXP_REPLACE(lost_proposals_fs,'([^-0-9])','') AS INT) AS lost_proposals_fs,
    NULLIF(TO_DATE(week_start, 'M/d/y'), '') AS dt_week_start,
    NULLIF(CAST(month AS INT), '') AS month,
    NULLIF(CAST(year AS INT), '') AS year
FROM
    datalake_gsheets_raw.target_nps_weekly
