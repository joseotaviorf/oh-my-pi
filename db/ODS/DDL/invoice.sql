drop table if exists invoice
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
	due_date date
)
;

create index invoice_contract_id_index
	on invoice (contract_id)
;

create index invoice_item_index
	on invoice (item)
;

create index invoice_year_month_index
	on invoice (year_month)
;

