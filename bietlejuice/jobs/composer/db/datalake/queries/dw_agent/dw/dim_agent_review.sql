SELECT -- TODO [ODS] we are following ODS current structure. The table structure should be updated later
    id_booking AS sk_agentreview,
    id_booking,
    rating,
    tag_other,
    is_punctual AS flg_punctuality,
    is_agent_well_informed AS flg_agent_well_informed,
    is_kind AS flg_kindness,
    is_not_kind AS flg_no_kindness,
    is_house_as_listing AS flg_house_as_listing,
    is_house_not_as_listing AS flg_house_not_as_listing,
    is_other_positive_reason AS flg_other_reason_positive,
    is_other_negative_reason AS flg_other_reason_negative,
    is_agent_late AS flg_agent_late,
    is_agent_without_inf AS flg_agent_with_no_info,
    ts_rating_created AS dt_rating,
    now() AS dt_timestamp
FROM
  datalake_ebdb_agents.agents_review