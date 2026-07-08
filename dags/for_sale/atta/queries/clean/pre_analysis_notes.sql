SELECT
    Id AS id,
    PreAnalysisId AS id_pre_analysis,
    UserId AS id_user,
    Observation AS notes,
    CreatedAt AS ts_created
FROM
    datalake_atta_raw.pre_analysis_observation
