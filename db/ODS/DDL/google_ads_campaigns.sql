CREATE TABLE public.google_ads_campaigns (
	campaign_id varchar(255) NOT NULL,
	campaign varchar(255) NOT NULL,
	device varchar(100) NOT NULL,
	start_date varchar(10) NOT NULL,
	"day" varchar(10) NOT NULL,
	impressions varchar(10) NOT NULL,
	clicks varchar(10) NOT NULL,
	cost varchar(30) NOT NULL,
	campaign_area varchar(20) NULL
)
WITH (
	OIDS=FALSE
) ;
