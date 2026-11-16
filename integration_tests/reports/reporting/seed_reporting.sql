create temp table sales as
select * from (values
  (1, 'apac', '2026-01', 100, 4),
  (2, 'apac', '2026-02', 150, 0),
  (3, 'apac', '2026-03', 0, 5),
  (4, 'emea', '2026-01', 50, 2),
  (5, 'emea', '2026-02', 25, null),
  (6, 'emea', '2026-03', 75, 3)
) t(id, region, month, amount, units);
create temp table events as
select * from (values
  (1, timestamp '2026-03-01 09:00:00', 'first'),
  (1, timestamp '2026-03-02 09:00:00', 'second'),
  (2, timestamp '2026-03-05 09:00:00', 'only'),
  (3, timestamp '2026-03-04 09:00:00', 'late'),
  (3, timestamp '2026-03-03 09:00:00', 'early')
) t(id, ts, note);
create temp table north as
select * from (values (1, 'a', 10), (2, 'b', 20)) t(id, name, Score);
create temp table south as
select * from (values (3, 'c', 'x'), (4, 'd', 'y')) t(ID, NAME, extra);
create temp table keys as
select * from (values ('a', 'b'), ('a', null), (null, 'b'), ('', 'b'), ('ab', null)) t(x, y);
