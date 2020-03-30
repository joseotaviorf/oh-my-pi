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
  "ts_last_listing" TIMESTAMP
)
WITH (oids = false);
