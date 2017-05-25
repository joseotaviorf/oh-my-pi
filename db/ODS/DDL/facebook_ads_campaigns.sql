DROP TABLE IF EXISTS public.facebook_ads_campaigns;
CREATE TABLE public.facebook_ads_campaigns (
	campaign_name varchar(255) NULL,
	"date" varchar(10) NULL,
	campaign_id varchar(255) NULL,
	spend varchar(30) NULL,
	account_name varchar(50) NULL
)
WITH (
	OIDS=FALSE
)
;