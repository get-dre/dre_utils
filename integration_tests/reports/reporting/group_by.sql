select region, month, sum(amount) as amount from sales {{ dre_utils.group_by(2) }} order by region, month
