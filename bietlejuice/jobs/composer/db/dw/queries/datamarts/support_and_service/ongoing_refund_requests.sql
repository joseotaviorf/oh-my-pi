with ongoing_refunds_requests as (
select 
	id as id_request,
	id_external_contract as id_contract,
	date(substring(json_format(json_extract(metadata, '$.requestedAt')),11,10)) as dt_requested,
	date(substring(json_extract_scalar(json_array_get(transition_list, 0), '$.createdAt["$date"]'),1,10)) as dt_analyzed,
	status,
	type,
    cast(json_extract(metadata,'$.expenses') as array(json)) as expenses,
	cast(json_extract(metadata,'$.auditableExpenses') as array(json)) as auditable_expenses
from datalake_heimdall_clean_prod.activity
where type in ('TENANT_REFUND_CONDOMINIUM','TENANT_REFUND_REPAIR')
)
select DISTINCT
	orr.id_request,
	cast(json_extract(t.expense,'$._id') as varchar) as id_expense,
	orr.id_contract,
	orr.status as request_status,
	orr.type as refund_type,
	cast(json_extract(t.expense,'$.text') as varchar) as expense_type,
	regexp_extract(cast(json_extract(t.expense,'$.text') as varchar),'^([a-zA-Zçáéíóúãõ]*)([\s\/])?',1) as expense_group,
	cast(json_extract(t.expense,'$.agreementChannel') as varchar) as expense_agreement_channel,
	cast(json_extract(t.expense,'$.amount') as double) as expense_amount,
	cast(json_extract(t.expense,'$.recurrenceType') as varchar) as expense_reccurence_type,
	cast(json_extract(json_extract(t.expense,'$.recurrencePayload'),'$.current') as bigint) as current_installment,
	cast(json_extract(json_extract(t.expense,'$.recurrencePayload'),'$.total') as bigint) as total_installments,
	cast(json_extract(u.auditable,'$.status') as varchar) as expense_status,
	cast(json_extract(u.auditable,'$.rejectionReason') as varchar) as expense_rejection_reason,
	cast(json_extract(u.auditable,'$.rejectionComment') as varchar) as expense_rejection_comment,
	cast(json_extract(t.expense,'$.isCustomText') as boolean) as is_custom_expense,
	date_diff('day', orr.dt_requested, orr.dt_analyzed) as days_requested_to_analyzed,
	orr.dt_requested,
	orr.dt_analyzed,
	NOW() as ts_load
from ongoing_refunds_requests orr
cross join unnest(expenses) as t(expense)
cross join unnest(auditable_expenses) as u(auditable)