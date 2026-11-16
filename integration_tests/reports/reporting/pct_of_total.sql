select region, sum(amount) as amount, {{ dre_utils.pct_of_total('sum(amount)') }} as share from sales {{ dre_utils.group_by(1) }} order by region
