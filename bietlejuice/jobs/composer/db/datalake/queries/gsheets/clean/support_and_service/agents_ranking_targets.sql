SELECT
    CAST(group AS INT) AS id_group,
    team,
    CAST(target_resolution AS FLOAT) AS target_resolution,
    CAST(target_csat AS FLOAT) AS target_csat,
    CAST(target_sla AS FLOAT) AS target_sla,
    CAST(productivity_target AS INT) AS productivity_target,
    CAST(ra_would_do_business_again_target AS FLOAT) AS ra_would_do_business_again_target,
    CAST(ra_target_score AS INT) AS ra_target_score,
    CAST(ra_target_solution_rate AS INT) AS ra_target_solution_rate,
    DATE(start_date) AS dt_start,
    DATE(end_date) AS dt_end
FROM
    datalake_gsheets_raw.agents_ranking_targets