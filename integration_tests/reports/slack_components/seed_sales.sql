create temp table sales as
select * from (values
  ('2026-03-16', 'apac', 10.5, 3),
  ('2026-03-16', 'emea', 7.0, 2),
  ('2026-03-17', 'apac', 12.0, 4),
  ('2026-03-18', 'apac', 9.5, 3),
  ('2026-03-18', 'emea', 8.25, 1)
) t(day, region, revenue, orders);
