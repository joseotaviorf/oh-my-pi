-- select * from Imovel_AUD
update Imovel_AUD
join
(
  select
    aud.id,
    aud.status, 
    min(rev) as rev
  FROM
    Imovel_AUD aud
  inner JOIN
  (
    select
      i.id
    from
      Imovel i
    left JOIN
    (
      select
        distinct id
      from
        v_ImovelStatusHistory 
       where
        status = 'publicado'
    ) h
      on i.id = h.id 
    where
      i.status = 'publicado'
      and h.id is null
      -- and i.id = 892764573
  ) i
  on aud.id = i.id
  group BY
    aud.id,
    aud.status
) ids
on ids.id = Imovel_AUD.id
  and ids.rev = Imovel_AUD.REV
 set  status_MOD = 1
where status_MOD is null