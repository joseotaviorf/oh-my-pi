DROP TABLE public.potential_listings;

CREATE TABLE public.potential_listings
(
  id bigint NOT NULL,
  ref_date timestamp without time zone,
  created_date timestamp without time zone,
  updated_date timestamp without time zone,
  attribution_id integer,
  attribution_uuid character varying(255) DEFAULT NULL::character varying,
  contact_date timestamp without time zone,
  lead_and_prospect_date timestamp without time zone,
  first_inside_sales_contact_date timestamp without time zone,
  qualified_date timestamp without time zone,
  opportunity_date timestamp without time zone,
  listing_publication_date timestamp without time zone,
  contract_date timestamp without time zone,
  lead_id integer,
  property_id integer,
  contract_id integer,
  renting_value integer,
  current_property_status character varying(255) DEFAULT NULL::character varying,
  dados_fotografo_id integer,
  owner_id integer,
  rep_id integer,
  manager_id integer DEFAULT 0,
  vendedor_id integer,
  tipo_admin character varying(255) DEFAULT NULL::character varying,
  imovel_attribution character varying(255) DEFAULT NULL::character varying,
  lead_tipo character varying(255) DEFAULT NULL::character varying,
  affiliate_listing_value numeric(12,4) DEFAULT NULL::numeric,
  affiliate_renting_value numeric(12,4) DEFAULT NULL::numeric,
  cac_affiliate numeric(12,4) DEFAULT NULL::numeric,
  cac_marketing numeric(12,4) NOT NULL DEFAULT 0.0000,
  cac_photo numeric(12,4) NOT NULL DEFAULT 0.0000,
  cac_inside_sales numeric(12,4) NOT NULL DEFAULT 0.0000,
  contact_to_lead_diff_minutes integer,
  lead_and_prospect_to_qualified_diff_minutes integer,
  qualified_to_opportunity_diff_minutes integer,
  opportunity_to_listing_diff_minutes integer,
  listing_to_1stcontract_diff_minutes integer,
  contact_to_listing_diff_minutes integer,
  contact_to_1stcontract_diff_minutes integer,
  CONSTRAINT potential_listings_pkey PRIMARY KEY (id)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.potential_listings
  OWNER TO "QuintoAndar";
