drop table if exists invoice.report;
create table invoice.report (
  contract_id bigint not null,
  version varchar,
  blocked boolean,
  "from" varchar,
  "to" varchar,
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
  year_month varchar -- column referred to the API date
);

create index invoice_contract_id_index
	on invoice.report (contract_id)
;

create index invoice_item_from_to_index
	on invoice.report (item, "from", "to")
;

create index invoice_year_month_index
	on invoice.report (year_month)
;

create index invoice_ref_item_ym_index
	on invoice.report (ref_item_ym)
;

create index invoice_tenant_status_index
	on invoice.report (tenant_status)
;
