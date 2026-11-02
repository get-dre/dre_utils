-- Every account id once: `account_id` and `Note`, an ordinary quoted name.
select 10 as account_id, 'first' as "Note", 1.0 as amount
union all select 11, 'second', 2.0
