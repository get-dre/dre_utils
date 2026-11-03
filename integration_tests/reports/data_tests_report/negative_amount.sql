-- A negative amount: `non_negative` fails on it.
select * from (values (6, 'north', 6.0), (7, 'south', -0.5)) t(account_id, region, amount)
