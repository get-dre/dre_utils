-- The region totals of accounts 1 and 2 (50.0 all told), with their sales under `sales`.
select * from (values ('north', 10.0), ('south', 40.0)) t(region, sales)
