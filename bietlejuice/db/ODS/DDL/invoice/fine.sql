drop table if exists invoice.fine;
create table invoice.fine
(
  contract_id bigint not null,
  fine decimal(14,2),
  due_date date,
  paid_date date,
  ym_partition varchar
)
;

create index invoice_fine_contract_id_index
	on invoice.fine (contract_id)
;

create index invoice_fines_ym_partition_index
	on invoice.fine (ym_partition)
;
