SELECT
    CAST(bonus_base AS INTEGER) AS bonus_base,
    CAST(bonus_boost AS INTEGER) AS bonus_boost,
    sk_user,
    CAST(target_base AS INTEGER) AS target_base,
    CAST(target_boost AS INTEGER) AS target_boost,
    year_month
FROM
    datalake_gsheets_raw.promotional_bonus_user_cluster_targets