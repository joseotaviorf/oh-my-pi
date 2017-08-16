drop table if exists invoice;
create table invoice
(
  contract_id bigint not null,
  version varchar,
  blocked boolean,
  "from" varchar,
  "to" varchar,
  description varchar,
  amount decimal(14,2),
  item varchar,
  year_month varchar,
  due_date date,
  tenant_due_date date,
  tenant_paid_date date,
  tenant_status varchar,
  landlord_due_date date,
  landlord_paid_date date,
  landlord_status varchar
)
;

create index invoice_contract_id_index
	on invoice (contract_id)
;

create index invoice_item_from_to_index
	on invoice (item, "from", "to")
;

create index invoice_year_month_index
	on invoice (year_month)
;

create index invoice_tenant_status_index
	on invoice (tenant_status)
;
