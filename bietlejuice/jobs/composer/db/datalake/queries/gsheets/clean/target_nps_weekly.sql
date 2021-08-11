SELECT
    CAST(REGEXP_REPLACE(nps_global,'([^0-9])','') AS INT) AS nps_global,
    CAST(REGEXP_REPLACE(nps_global_4060_l4w,'([^0-9])','') AS INT) AS nps_global_4060_l4w,
    CAST(REGEXP_REPLACE(lost_l4w,'([^0-9])','') AS INT) AS lost_l4w,
    CAST(REGEXP_REPLACE(visits_iq_l4w,'([^0-9])','') AS INT) AS visits_iq_l4w,
    CAST(REGEXP_REPLACE(propostas_iq_l4w,'([^0-9])','') AS INT) AS propostas_iq_l4w,
    CAST(REGEXP_REPLACE(unpublished_pp_l4w,'([^0-9])','') AS INT) AS unpublished_pp_l4w,
    CAST(REGEXP_REPLACE(true_l4w,'([^0-9])','') AS INT) AS true_l4w,
    CAST(REGEXP_REPLACE(onboarding_l4w,'([^0-9])','') AS INT) AS onboarding_l4w,
    CAST(REGEXP_REPLACE(ongoing_l4w,'([^0-9])','') AS INT) AS ongoing_l4w,
    CAST(REGEXP_REPLACE(offboarding_l4w,'([^0-9])','') AS INT) AS offboarding_l4w,
    CAST(REGEXP_REPLACE(lost_rejetcted,'([^0-9])','') AS INT) AS lost_rejetcted,
    CAST(REGEXP_REPLACE(fs_true,'([^0-9])','') AS INT) AS fs_true,
    CAST(REGEXP_REPLACE(fs_lost,'([^0-9])','') AS INT) AS fs_lost,
    CAST(REGEXP_REPLACE(ccv,'([^0-9])','') AS INT) AS ccv,
    CAST(REGEXP_REPLACE(registry,'([^0-9])','') AS INT) AS registry,
    CAST(REGEXP_REPLACE(unpublished_fs,'([^0-9])','') AS INT) AS unpublished_fs,
    CAST(REGEXP_REPLACE(lost_visits_fs,'([^0-9])','') AS INT) AS lost_visits_fs,
    CAST(REGEXP_REPLACE(lost_proposals_fs,'([^0-9])','') AS INT) AS lost_proposals_fs,
    NULLIF(week_start, '') AS week_start,
    NULLIF(CAST(month AS INT), '') AS month,
    NULLIF(CAST(year AS INT), '') AS year
FROM
    datalake_gsheets_raw.target_nps_weekly