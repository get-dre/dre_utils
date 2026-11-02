-- The same, except `south` is 0.02 short: a rounding difference.
select * from (values ('north', 10.0), ('south', 39.98)) t(region, total)
