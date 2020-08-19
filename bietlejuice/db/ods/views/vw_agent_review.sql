--DROP VIEW IF EXISTS vw_dim_agent_review;
--CREATE VIEW vw_dim_agent_review AS
SELECT
    id_booking AS sk_agentreview,
	id_booking,
	rating,
	tag_other,
	flg_punctuality,
	flg_agent_well_informed,
	flg_kindness,
	flg_no_kindness,
	flg_house_as_listing,
	flg_house_not_as_listing,
	flg_other_reason_positive,
	flg_other_reason_negative,
	flg_agent_late,
	flg_agent_with_no_info,
	dt_rating,
    now() as dt_timestamp
FROM
  public.agent_review ;
