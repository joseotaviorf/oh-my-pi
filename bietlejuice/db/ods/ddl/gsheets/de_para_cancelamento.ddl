drop table if exists gsheets.de_para_cancelamento;
create table gsheets.de_para_cancelamento
(
   count varchar(6),
   new_reason varchar(100),
   reason varchar(364),
   reason_category varchar(6),
   responsible varchar(100)
);