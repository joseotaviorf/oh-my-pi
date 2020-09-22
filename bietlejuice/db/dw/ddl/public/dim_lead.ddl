drop table if exists dim_lead;
create table if not exists dim_lead
(
 sk_lead bigint   encode az64                                            
 ,id bigint   encode az64
 ,area_total integer   encode az64
 ,bairro varchar(200)   encode lzo
 ,captado_em date   encode az64
 ,cep varchar(9)   encode lzo
 ,cidade varchar(200)   encode lzo
 ,complemento varchar(500)   encode lzo
 ,endereco varchar(200)   encode lzo
 ,nome_anunciante varchar(255)   encode lzo
 ,numero varchar(200)   encode lzo
 ,numero_banheiros integer   encode az64
 ,numero_quartos integer   encode az64
 ,numero_suites integer   encode az64
 ,url_anuncio varchar(255)   encode lzo
 ,telefone_anunciante varchar(100)   encode lzo
 ,tipo varchar(255)   encode lzo
 ,email varchar(250)   encode lzo
 ,email_captador varchar(250)   encode lzo
 ,telefone_captador varchar(250)   encode lzo
 ,dentro_area_atuacao integer   encode az64
 ,lat numeric(10,7)   encode az64
 ,lng numeric(10,7)   encode az64
 ,condominio integer   encode az64
 ,iptu integer   encode az64
 ,ub_page_variant varchar(255)   encode lzo
 ,reason varchar(255)   encode lzo
 ,reason_detail varchar(255)   encode lzo
 ,deadline_of_new_contact varchar(255)   encode lzo
 ,status varchar(255)   encode lzo
 ,processado smallint   encode az64
 ,origem varchar(255)   encode lzo
 ,is_enriched_data boolean
 ,external_id varchar(255)   encode lzo
 ,mencionar integer   encode az64
 ,automatically_discarded integer   encode az64
 ,proprietario_nome varchar(255)   encode lzo
 ,proprietario_email varchar(255)   encode lzo
 ,affiliate_type varchar(256)   encode lzo
 ,dados_afiliado_inicio_atuacao timestamp without time zone   encode az64
 ,dados_afiliado_cidade_atuacao varchar(100)   encode lzo
 ,region_id integer   encode az64
 ,atualizado_em timestamp without time zone   encode az64
 ,criado_em timestamp without time zone   encode az64
 ,utm_source varchar(255)   encode lzo
 ,utm_medium varchar(255)   encode lzo
 ,utm_campaign varchar(255)   encode lzo
 ,utm_content varchar(255)   encode lzo
 ,utm_term varchar(255)   encode lzo
 ,tracking_platform varchar(255)   encode lzo
 ,tracking_region varchar(255)   encode lzo
 ,tracking_city varchar(255)   encode lzo
 ,network varchar(255)   encode lzo
 ,usuario_que_indicou_id varchar(255)   encode lzo
 ,score_factor bigint   encode az64
 ,is_b2b boolean
 ,b2b_type varchar(256)   encode lzo
 ,sales_company varchar(255)   encode lzo
 ,ts_sales_company_sent timestamp without time zone   encode az64
 ,sale_price bigint   encode az64
 ,is_for_rent boolean
 ,is_for_sale boolean
 ,load_timestamp timestamp without time zone   encode az64
)
diststyle key
distkey (sk_lead)
;
