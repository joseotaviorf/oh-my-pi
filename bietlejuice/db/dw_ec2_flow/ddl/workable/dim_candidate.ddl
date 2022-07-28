drop table if exists workable.dim_candidate;
create table if not exists workable.dim_candidate (
  sk_candidate varchar not null,
  name varchar,
  first_name varchar,
  last_name varchar,
  headline varchar,
  account_subdomain varchar,
  account_name varchar,
  stage varchar,
  disqualified varchar,
  disqualification_reason varchar,
  sourced varchar,
  profile_url varchar,
  email varchar,
  domain varchar,
  created_at varchar,
  updated_at varchar,
  hired_at varchar
)
;