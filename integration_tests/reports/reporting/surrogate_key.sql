select x, y, {{ dre_utils.surrogate_key(['x', 'y']) }} as k from keys order by k
