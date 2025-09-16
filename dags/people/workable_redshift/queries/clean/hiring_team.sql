SELECT
    ht.id,
    ht.job_id AS id_job,
    ht.member_id AS id_member,
    ht.job_title,
    ht.member_name,
    ht.role,
    ht.member_joined_job_hiring_team_at AS ts_member_joined_job_hiring_team,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.hiring_team AS ht
