local formats = {
	TaggedProperty = "JEXP_TAGGED_%s_%s"
}

local JexpTags = {
	Formats = formats
}

function JexpTags.getTaggedPropertyTag(propName: string, targetedValue: string)
	return formats.TaggedProperty:format(propName, targetedValue)
end

return JexpTags