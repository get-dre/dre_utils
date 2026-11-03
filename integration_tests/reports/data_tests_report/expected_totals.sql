-- Each region's total, as `totals_pass` and the detail `account_totals` should add up to.
select * from (values ('north', 10.0), ('south', 40.0)) t(region, total)
