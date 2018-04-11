CREATE EXTERNAL TABLE datalake_raw.zendesk_user (
	id string,
	email string,
	name string ,
	active boolean ,
	alias string ,
	chat_only boolean ,
	created_at timestamp ,
	custom_role_id int,
	details string ,
	external_id int ,
	last_login_at timestamp ,
	locale string ,
	locale_id int ,
	moderator boolean ,
	notes string ,
	only_private_comments boolean ,
	organization_id string ,
	default_group_id string ,
	phone string ,
	photo_id int ,
	restricted_agent boolean ,
	role string ,
	shared boolean ,
	shared_agent boolean ,
	signature string ,
	suspended boolean ,
	ticket_restriction string ,
	time_zone string ,
	two_factor_auth_enabled boolean ,
	updated_at timestamp ,
	url string ,
	verified boolean,
	user_fields struct<
		cd_imvel:int,
		preferencia_de_contato:string,
		observaes_e_historico:string,
		organizao:string,
		vip:string
	>
)
PARTITIONED BY (extracted_date date)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-datalake/raw/zendesk/users/';

