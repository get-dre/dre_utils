-- Account 1 appears twice: one failure row, with its count.
select 1 as account_id, 'first' as "Note", 1.0 as amount
union all select 2, 'second', 2.0
union all select 3, 'third', 3.0
union all select 4, 'fourth', 4.0
union all select 1, 'again', 5.0
