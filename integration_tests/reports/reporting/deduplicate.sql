select * from ({{ dre_utils.deduplicate('events', 'id', 'ts') }}) e order by id
