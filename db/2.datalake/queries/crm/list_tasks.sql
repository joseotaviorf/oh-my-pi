select
	_id,  
  type,
  datainicio as start_date,
  realizadaem as performed_date,
  imovelid as property_id,
  authorid as author_id,
  authorname as author_name,
  assigneeid as assignee_id,
  assigneename as assignee_name,
  workgroupid as workgroup_id,
  workgrouptitle as workgroup_title,
  destinatarioid as recipient_id,
  status,
  substring(descricao, 1, 200)  as description,
  titulo as title,
  extracted_on
from
	datalake_raw.crm_tasks
where
	extracted_on = cast('{}' as date)