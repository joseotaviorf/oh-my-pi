WITH metric_period_process AS (
    SELECT DISTINCT
        mp.id,
        mp.metric,
        mp.dt_init,
        mp.dt_end,
        -- keeping partitions immutable for the merge on function
        YEAR(mp.dt_init) AS year,
        MONTH(mp.dt_init) AS month,
        DAY(mp.dt_init) AS day
    FROM
        datalake_big_agent_clean.metric_period AS mp
    JOIN
        datalake_quintoandar.aux_date AS ad
            ON ad.date BETWEEN mp.dt_init AND mp.dt_end
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND mp.status = "VALID"
)
SELECT 
    mp.id AS id_metric_period,
    mha.id_member_profile,
    -- get the last updated id_user, considering the merge of user ids in EBDB
    u.id_main_user AS id_user,
    u.id_agent,
    u.uuid_person,
    u_parent.id_main_user AS id_parent_user,
    u_parent.id_agent AS id_parent_agent,
    u_parent.uuid_person AS uuid_parent_person,
    mha.id_business_unit,
    mha.hub_name,
    mha.profile,
    mp.dt_init AS dt_reference,
    mp.year,
    mp.month,
    mp.day
FROM
    datalake_hub_services.member_hub_allocation AS mha
JOIN
    metric_period_process AS mp
        ON DATE(mha.dt_reference) BETWEEN mp.dt_init AND mp.dt_end
JOIN
    datalake_hub_services.users AS u 
        ON u.id_user = mha.id_user
LEFT JOIN 
    datalake_hub_services.users AS u_parent
        ON u_parent.id_user = mha.id_parent_user
WHERE
    mha.profile IN ('AGENT', 'NEGOTIATION_EXECUTIVE')
    AND mha.id_agent IS NOT NULL
QUALIFY
    1 = ROW_NUMBER() OVER(PARTITION BY mp.id, u.id_main_user ORDER BY mha.dt_reference DESC)