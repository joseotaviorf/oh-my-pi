-- Table: public.contacts_and_prospects

DROP TABLE if exists public.contacts_and_prospects;

CREATE TABLE public.contacts_and_prospects
(
  
  cap_id bigint NOT NULL DEFAULT '0'::bigint,
  lead_id bigint,
  imovel_id bigint,
  anuncio_criado_em date,
  area_total integer,
  bairro character varying(200) DEFAULT NULL::character varying,
  cep character varying(200) DEFAULT NULL::character varying,
  cidade character varying(200) DEFAULT NULL::character varying,
  complemento character varying(200) DEFAULT NULL::character varying,
  endereco character varying(200) DEFAULT NULL::character varying,
  numero character varying(200) DEFAULT NULL::character varying,
  numero_banheiros integer,
  numero_quartos integer,
  numero_suites integer,
  url_anuncio character varying(255) DEFAULT NULL::character varying,
  valor integer,
  telefone_anunciante character varying(100) DEFAULT NULL::character varying,
  tipo character varying(255) DEFAULT NULL::character varying,
  email character varying(250) DEFAULT NULL::character varying,
  lat numeric(10,7) DEFAULT NULL::numeric,
  lng numeric(10,7) DEFAULT NULL::numeric,
  condominio integer,
  iptu integer,
  reason character varying(255) DEFAULT NULL::character varying,
  status character varying(255) DEFAULT NULL::character varying,
  envio_email_apresentacao_pos timestamp without time zone,
  envio_email_apresentacao_pre timestamp without time zone,
  processado smallint,
  origem character varying(255) DEFAULT NULL::character varying,
  external_id character varying(255) DEFAULT NULL::character varying,
  mencionar integer,
  automatically_discarded integer,
  estado_nome character varying(255) DEFAULT NULL::character varying,
  estado_abrev character varying(255) DEFAULT NULL::character varying,
  dados_afiliado_tipo_afiliado character varying(255) DEFAULT NULL::character varying,
  dados_afiliado_inicio_atuacao timestamp without time zone,
  dados_afiliado_cidade_atuacao character varying(100) DEFAULT NULL::character varying,
  region_id integer,
  atualizado_em timestamp without time zone,
  url_source character varying(100) DEFAULT NULL::character varying,
  utm_medium character varying(100) DEFAULT NULL::character varying,
  utm_campaign character varying(255) DEFAULT NULL::character varying,
  utm_source character varying(100) DEFAULT NULL::character varying,
  usuario_que_indicou_id integer DEFAULT NULL,
  usuario_que_cadastrou_id integer DEFAULT NULL,
  self_service integer,
  attribution_type character varying(100) DEFAULT NULL::character varying,
  flow character varying(100) DEFAULT NULL::character varying
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.contacts_and_prospects
  OWNER TO "QuintoAndar";
