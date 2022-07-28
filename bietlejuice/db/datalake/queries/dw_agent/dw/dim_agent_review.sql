SELECT -- TODO [ODS] we are following ODS current structure. The table structure should be updated later
    id_booking AS sk_agentreview,
    id_booking AS sk_booking,
    rating,
    tag_other,
    CAST(is_punctual AS INTEGER) AS flg_punctuality,
    CAST(is_agent_well_informed AS INTEGER) AS flg_agent_well_informed,
    CAST(is_kind AS INTEGER) AS flg_kindness,
    CAST(is_not_kind AS INTEGER) AS flg_no_kindness,
    CAST(is_house_as_listing AS INTEGER) AS flg_house_as_listing,
    CAST(is_house_not_as_listing AS INTEGER) AS flg_house_not_as_listing,
    CAST(is_other_positive_reason AS INTEGER) AS flg_other_reason_positive,
    CAST(is_other_negative_reason AS INTEGER) AS flg_other_reason_negative,
    CAST(is_agent_late AS INTEGER) AS flg_agent_late,
    CAST(is_agent_without_info AS INTEGER) AS flg_agent_with_no_info,
    ts_rating_created AS dt_rating,
    now() AS dt_timestamp
FROM
  datalake_ebdb_agents.agents_review