drop table if exists invoice.fine;
create table invoice.fine
(
  contract_id bigint not null,
  fine decimal(14,2),
  due_date date,
  paid_date date,
  year_month varchar
)
;

create index invoice_fine_contract_id_index
	on invoice.fine (contract_id)
;

create index invoice_fines_year_month_index
	on invoice.fine (year_month)
;
