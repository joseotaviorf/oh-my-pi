DROP TABLE IF EXISTS public.dim_agent_review;
CREATE TABLE public.dim_agent_review (
    "sk_agentreview" bigint NOT NULL,
	"sk_booking" bigint NOT NULL,
	"rating" int,
	"tag_other" varchar(500) NULL,
	"flg_punctuality" int NULL,
	"flg_agent_well_informed" int NULL,
	"flg_kindness" int NULL,
	"flg_no_kindness" int NULL,
	"flg_house_as_listing" int NULL,
	"flg_house_not_as_listing" int NULL,
	"flg_other_reason_positive" int NULL,
	"flg_other_reason_negative" int NULL,
	"flg_agent_late" int NULL,
	"flg_agent_with_no_info" int,
  PRIMARY KEY ("sk_agentreview")
)