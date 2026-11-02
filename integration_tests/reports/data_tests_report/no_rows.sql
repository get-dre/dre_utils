-- No accounts at all: `not_empty` finds the report empty.
select cast(null as integer) as account_id, 'east' as region, 0.0 as amount where false
