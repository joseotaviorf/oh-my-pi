DROP TABLE IF EXISTS public.listing_business_context;
CREATE TABLE public.listing_business_context (
  "id" BIGINT NOT NULL,
  "id_house" BIGINT,
  "business_context" VARCHAR(255),
  "status" VARCHAR(255),
  "status_reason" VARCHAR(255),
  "ts_created" TIMESTAMP,
  "ts_updated" TIMESTAMP,
  "ts_first_listing" TIMESTAMP,
  "ts_last_listing" TIMESTAMP,
  "ts_opt_out_rent" TIMESTAMP,
  "ts_opt_out_sale" TIMESTAMP,
  "user_listing_registrant_rent" BIGINT,
  "user_listing_registrant_sale" BIGINT
)
WITH (oids = false);
