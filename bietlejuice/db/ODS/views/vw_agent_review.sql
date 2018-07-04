DROP VIEW IF EXISTS vw_dim_agent_review;
CREATE VIEW vw_dim_agent_review
AS
SELECT
    id_booking AS sk_agentreview,
	id_booking,
	rating,
	tag_other,
	tag_punctuality,
	tag_agent_well_informed,
	tag_kindness,
	tag_no_kindness,
	tag_house_as_listing,
	tag_house_not_as_listing,
	tag_other_reason_positive,
	tag_other_reason_negative,
	tag_agent_late,
	tag_agent_with_no_info
FROM
  public.agent_review ;
