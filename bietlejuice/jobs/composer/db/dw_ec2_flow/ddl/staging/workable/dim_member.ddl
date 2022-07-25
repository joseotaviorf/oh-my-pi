drop table if exists staging.workable_dim_member;
create table if not exists staging.workable_dim_member (
	sk_member varchar not null,
	name varchar,
	email varchar,
	headline varchar,
	role varchar
)
;