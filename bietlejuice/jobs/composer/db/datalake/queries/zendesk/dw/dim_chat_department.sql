select
	id as sk_chat_department,
	name,
	description,
	is_enabled,
	left(members, 2000) as members,
	now() as ts_load
from datalake_zendesk_clean.chats_departments
