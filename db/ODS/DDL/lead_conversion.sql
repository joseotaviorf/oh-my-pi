DROP TABLE IF EXISTS public.lead_conversion;
CREATE TABLE lead_conversion (
  id integer NOT NULL,
  imovel_id integer NOT NULL,
  "leadConvertido_id" integer DEFAULT NULL,
  vendedor_id integer DEFAULT NULL,
  "gerenteContas_id" integer DEFAULT NULL,
  validado integer DEFAULT NULL,
  status varchar(255) DEFAULT NULL,
  tipo varchar(31) NOT NULL,
  "dataConversao" datetime NOT NULL,
  "atualizadoEm" datetime DEFAULT NULL,
  "criadoEm" datetime DEFAULT NULL
) WITH (oids = false);
