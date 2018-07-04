DROP TABLE IF EXISTS public.dim_agent_review;
CREATE TABLE public.dim_agent_review (
    "sk_agentreview" bigint NOT NULL,
	"sk_booking" bigint NOT NULL,
	"rating" integer,
	"tag_other" varchar(500) NULL,
	"flg_punctuality" integer NULL,
	"flg_agent_well_informed" integer NULL,
	"flg_kindness" integer NULL,
	"flg_no_kindness" integer NULL,
	"flg_house_as_listing" integer NULL,
	"flg_house_not_as_listing" integer NULL,
	"flg_other_reason_positive" integer NULL,
	"flg_other_reason_negative" integer NULL,
	"flg_agent_late" integer NULL,
	"flg_agent_with_no_info" integer,
  CONSTRAINT dim_agent_review_pkey PRIMARY KEY(sk_agentreview)
)