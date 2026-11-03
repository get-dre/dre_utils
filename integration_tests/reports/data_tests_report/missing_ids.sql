-- The second account's id is missing.
select * from (values (5, 'west', 1.0), (cast(null as integer), 'west', 2.0)) t(account_id, region, amount)
