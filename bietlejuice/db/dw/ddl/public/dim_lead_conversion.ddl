DROP TABLE IF EXISTS public.dim_lead_conversion;
CREATE TABLE public.dim_lead_conversion (
  sk_lead_conversion INTEGER,
  id_lead_conversion INTEGER,
  id_imovel INTEGER,
  id_converted_lead INTEGER,
  id_salesperson INTEGER,
  id_account_manager INTEGER,
  validated INTEGER,
  status VARCHAR(255),
  type VARCHAR(31),
  dt_conversion TIMESTAMP,
  dt_created TIMESTAMP,
  dt_updated TIMESTAMP,
  dt_timestamp TIMESTAMP WITHOUT TIME ZONE,
  CONSTRAINT dim_lead_conversion_pkey PRIMARY KEY(sk_lead_conversion)
) ;