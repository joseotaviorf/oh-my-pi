drop table if exists offer;
create table offer (
  id bigint not null,
  atualizado_em timestamp,
  approved_date timestamp,
  criado_em timestamp,
  firestore_id varchar(255),
  godfather_id bigint,
  original_condo bigint,
  original_home_insurance bigint,
  original_iptu bigint,
  original_rent bigint,
  rent bigint,
  status varchar(255),
  turn varchar(255),
  client_id bigint,
  house_id bigint,
  rent_flow_id bigint,
  rejection_reason varchar(255),
  iteration integer,
  expiration_date datetime,
  type varchar(255),
  first_sent_at datetime,
  last_sent_at datetime,
  topic_type varchar(255)
)
;

