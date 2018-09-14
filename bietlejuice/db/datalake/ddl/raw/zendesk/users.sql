-- TODO: Precisamos entender melhor a declaração dessa tabela, e a gravação dos arquivos no S3
drop table if exists datalake_raw.zendesk_users;

CREATE EXTERNAL TABLE datalake_raw.zendesk_users (
		`pa` struct<
			id:string,
			email:string,
			name:string,
			active:string ,
			alias:string ,
			chat_only:string ,
			created_at:string ,
			custom_role_id:int,
			details:string ,
			external_id:int ,
			last_login_at:string ,
			locale:string ,
			locale_id:int ,
			moderator:string ,
			notes:string ,
			only_private_comments:string ,
			organization_id:string ,
			default_group_id:string ,
			phone:string ,
			photo_id:int ,
			restricted_agent:string ,
			role:string ,
			shared:string ,
			shared_agent:string ,
			signature:string ,
			suspended:string ,
			ticket_restriction:string ,
			time_zone:string ,
			two_factor_auth_enabled:string ,
			updated_at:string ,
			url:string ,
			verified:string,
			user_fields:struct<
					cd_imvel:int,
					preferencia_de_contato:string,
					observaes_e_historico:string,
					organizao:string,
					vip:string
			>,
			tags:array<string>
		>
)
-- PARTITIONED BY (extracted_date date)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
      "paths" = "pa" -- pa = path array -> necessário devido ao formato atual do arquivo no S3 [{id=111},{id=222}]
   )
LOCATION 's3://5a-datalake/raw/zendesk/users/';

MSCK REPAIR table datalake_raw.zendesk_users;

select pa.tags from datalake_raw.zendesk_users where cardinality(pa.tags) > 0 limit 10

