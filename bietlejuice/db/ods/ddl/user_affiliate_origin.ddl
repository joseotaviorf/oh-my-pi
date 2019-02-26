DROP TABLE if exists public.user_affiliate_origin;

CREATE TABLE public.user_affiliate_origin
(
    user_id bigint,
	utm_source varchar(255),
	utm_medium varchar(255),
	utm_campaign varchar(255),
	platform varchar(255),
	device_type varchar(255),
	country varchar(255),
	region varchar(255),
	city varchar(255),
	client_signup_event_time timestamp
)
WITH (
  OIDS=FALSE
);