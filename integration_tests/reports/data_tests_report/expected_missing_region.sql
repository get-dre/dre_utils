-- The same, except a `west` total appears that the detail doesn't have.
select * from (values ('north', 10.0), ('south', 40.0), ('west', 7.0)) t(region, total)
