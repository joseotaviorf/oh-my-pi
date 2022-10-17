WITH total_per_agent AS (
  SELECT
    sa.id_external_agent,
    sa.external_agent_name,
    sa.agent_email,
    sa.channel,
    SUM(
      CAST(
          CASE
              WHEN si.status = 'Respondido' THEN TRUE
              ELSE FALSE
          END
      AS SMALLINT)
    ) AS non_moderator_productivity,
    SUM(
      CAST(
          CASE
              WHEN lower(si.status) IN ('em espera', 'ignorado', 'aberto') THEN TRUE
              ELSE FALSE
          END
      AS SMALLINT)
    ) AS moderator_productivity,
    SUM(
      CASE
        WHEN si.minutes_changed_status IS NOT NULL THEN minutes_changed_status
        ELSE 0
      END
    ) AS total_minutes_changed_status,
    SUM(
      CAST(
          CASE
              WHEN si.is_sla_achieved IS TRUE THEN TRUE
              ELSE FALSE
          END
      AS SMALLINT)
    ) AS total_sla_achievement,
    SUM(
      CAST(
          CASE
              WHEN si.is_first_answer IS TRUE THEN TRUE
              ELSE FALSE
          END
      AS SMALLINT)
    ) AS total_first_answer,
    sa.is_moderator,
    DATE(ts_load) AS dt_ref
  FROM
    datalake_stilingue.service_interactions si
  LEFT JOIN
    datalake_gsheets_clean.stilingue_agents sa
      ON si.agent LIKE CONCAT("%",sa.external_agent_name,"%")
  WHERE
    si.agent IS NOT NULL
  GROUP BY 1, 2, 3, 4, 10, 11
)
SELECT
  ac.id_assignee AS id_agent,
  t.id_external_agent,
  t.external_agent_name,
  t.agent_email,
  t.channel,
  t.is_moderator,
  t.non_moderator_productivity,
  t.moderator_productivity,
  CASE
    WHEN t.is_moderator IS FALSE THEN t.non_moderator_productivity
    WHEN t.channel <> 'Moderação' AND t.is_moderator IS TRUE THEN t.non_moderator_productivity + t.moderator_productivity
    WHEN t.channel = 'Moderação' AND t.is_moderator IS TRUE THEN t.moderator_productivity
  END AS agent_productivity,
  t.total_first_answer,
  t.total_sla_achievement,
  t.total_minutes_changed_status,
  t.total_minutes_changed_status/(t.non_moderator_productivity + t.moderator_productivity) AS average_service_minutes,
  t.dt_ref
FROM
  total_per_agent t
LEFT JOIN
  datalake_gsheets_clean.agents_control ac
    ON ac.email = t.agent_email