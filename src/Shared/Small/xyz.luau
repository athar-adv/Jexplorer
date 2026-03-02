return function(str: string): (any, any, any)
	return (string.match :: any)(str, "%s*([%d.-]*)%s*,%s*([%d.-]*)%s*,%s*([%d.-]*)%s*")
end