drop table if exists workable.dim_member;
create table if not exists workable.dim_member (
	sk_member varchar not null,
	name varchar,
	email varchar,
	headline varchar,
	role varchar
)
;