-- `expected_off_by_cents` is 0.01 short in `south`; tolerance 0.05.
select 'north' as region, 10.0 as total union all select 'south', 39.99
