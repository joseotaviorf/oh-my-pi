DROP TABLE IF EXISTS public.dim_agent_review;
CREATE TABLE public.dim_agent_review (
    "sk_agentreview" bigint NOT NULL,
	"id_booking" bigint NOT NULL,
	"rating" int,
	"tag_other" varchar(500) NULL,
	"tag_punctuality" int NULL,
	"tag_agent_well_informed" int NULL,
	"tag_kindness" int NULL,
	"tag_no_kindness" int NULL,
	"tag_house_as_listing" int NULL,
	"tag_house_not_as_listing" int NULL,
	"tag_other_reason_positive" int NULL,
	"tag_other_reason_negative" int NULL,
	"tag_agent_late" int NULL,
	"tag_agent_with_no_info" int,
  PRIMARY KEY ("sk_agentreview")
)