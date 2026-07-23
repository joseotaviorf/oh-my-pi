WITH metric_period_process AS (
  SELECT DISTINCT
    mp.id,
    mp.metric,
    mp.dt_init,
    mp.dt_end,
    YEAR(TO_DATE(mp.dt_init)) AS year, /* keeping partitions immutable for the merge on function */
    MONTH(TO_DATE(mp.dt_init)) AS month,
    DAY(TO_DATE(mp.dt_init)) AS day
  FROM datalake_tiers.metric_period AS mp
  JOIN datalake_quintoandar.aux_date AS ad
    ON ad.date BETWEEN mp.dt_init AND mp.dt_end
  WHERE
    ad.date BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
    AND mp.status = 'VALID'
)
SELECT
  id_metric_period,
  id_member_profile,
  id_user,
  id_agent,
  uuid_person,
  id_parent_user,
  id_parent_agent,
  uuid_parent_person,
  id_business_unit,
  hub_name,
  profile,
  dt_reference,
  year,
  month,
  day
FROM (
  SELECT
    mp.id AS id_metric_period,
    mha.id_member_profile,
    u.id_main_user AS id_user, /* get the last updated id_user, considering the merge of user ids in EBDB */
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
    mp.day,
    ROW_NUMBER() OVER (PARTITION BY mp.id, u.id_main_user ORDER BY IF(NOT u_parent.id_main_user IS NULL, 1, 0) DESC, mp.dt_init DESC) AS _w,
    mp.id,
    u.id_main_user
  FROM datalake_hub_services.member_hub_allocation AS mha
  JOIN metric_period_process AS mp
    ON CAST(mha.dt_reference AS DATE) BETWEEN mp.dt_init AND mp.dt_end
  JOIN datalake_hub_services.users AS u
    ON u.id_user = mha.id_user
  LEFT JOIN datalake_hub_services.users AS u_parent
    ON u_parent.id_user = mha.id_parent_user
  WHERE
    mha.profile IN ('AGENT', 'NEGOTIATION_EXECUTIVE') AND NOT mha.id_agent IS NULL
) AS _t
WHERE
  1 = _w