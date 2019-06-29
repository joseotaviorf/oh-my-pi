drop table if exists offer;
create table if not exists offer (
  id bigint not null,
  atualizado_em timestamp,
  analysis_date timestamp,
  criado_em timestamp,
  firestore_id varchar(255),
  godfather_id bigint,
  original_condo bigint,
  original_home_insurance bigint,
  original_iptu bigint,
  original_rent bigint,
  last_rent bigint,
  status varchar(255),
  turn varchar(255),
  client_id bigint,
  house_id bigint,
  rent_flow_id bigint,
  rejection_reason varchar(255),
  iteration integer,
  expiration_date timestamp,
  type varchar(255),
  first_sent_at timestamp,
  last_sent_at timestamp,
  topic_type varchar(255),
  last_rent_offered_by_tenant numeric(18,4),
  last_rent_offered_by_owner numeric(18,4)
);

