DROP TABLE IF EXISTS public.agent_review;
CREATE TABLE public.agent_review (
	"id_booking" bigint NOT NULL,
	"rating" INTEGER,
	"tag_other" VARCHAR(500) NULL,
	"flg_punctuality" INTEGER NULL,
	"flg_agent_well_informed" INTEGER NULL,
	"flg_kindness" INTEGER NULL,
	"flg_no_kindness" INTEGER NULL,
	"flg_house_as_listing" INTEGER NULL,
	"flg_house_not_as_listing" INTEGER NULL,
	"flg_other_reason_positive" INTEGER NULL,
	"flg_other_reason_negative" INTEGER NULL,
	"flg_agent_late" INTEGER NULL,
	"flg_agent_with_no_info" INTEGER,
  PRIMARY KEY ("id_booking")
)