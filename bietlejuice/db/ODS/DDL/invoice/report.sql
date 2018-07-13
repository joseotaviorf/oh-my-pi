drop table if exists invoice.report;
create table invoice.report (
  contract_id bigint not null,
  version varchar,
  blocked boolean,
  _from varchar,
  _to varchar,
  description varchar,
  amount decimal(14,2),
  item varchar,
  ref_item_ym varchar, -- column referred to the item year-month
  due_date date,
  tenant_due_date date,
  tenant_paid_date date,
  tenant_status varchar,
  landlord_due_date date,
  landlord_paid_date date,
  landlord_status varchar,
  delayed_days smallint,
  ym_partition varchar, -- column referred to the API date
  purpose varchar
);

create index invoice_contract_id_index
	on invoice.report (contract_id)
;

create index invoice_item_from_to_index
	on invoice.report (item, _from, _to)
;

create index invoice_ym_partition_index
	on invoice.report (ym_partition)
;

create index invoice_ref_item_ym_index
	on invoice.report (ref_item_ym)
;

create index invoice_tenant_status_index
	on invoice.report (tenant_status)
;
