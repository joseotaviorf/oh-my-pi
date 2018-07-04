DROP TABLE IF EXISTS public.agent_review;
CREATE TABLE public.agent_review (
	"id_booking" bigint NOT NULL,
	"rating" INTEGER,
	"tag_other" VARCHAR(500) NULL,
	"tag_punctuality" INTEGER NULL,
	"tag_agent_well_informed" INTEGER NULL,
	"tag_kindness" INTEGER NULL,
	"tag_no_kindness" INTEGER NULL,
	"tag_house_as_listing" INTEGER NULL,
	"tag_house_not_as_listing" INTEGER NULL,
	"tag_other_reason_positive" INTEGER NULL,
	"tag_other_reason_negative" INTEGER NULL,
	"tag_agent_late" INTEGER NULL,
	"tag_agent_with_no_info" INTEGER,
  PRIMARY KEY ("id_booking")
)