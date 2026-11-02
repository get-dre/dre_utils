{{ seed_data_tests() }}
-- A view: the source checks see it, and reading it evaluates it again.
create temp view empty_view as select cast(null as double) as amount where false
