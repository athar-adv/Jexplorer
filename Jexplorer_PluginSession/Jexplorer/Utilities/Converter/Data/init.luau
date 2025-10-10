--!optimize 2
--!native
--!strict

local WRITE_BUFFER = buffer.create(script.Parent:GetAttribute("WriteBufferSize"))

local SpecialCFrames = require(script.SpecialCFrames)
local extypeof = require(script.Parent.ExtendedTypeof)
local ByteTag = require(script.ByteTag)
local t = require(script.Parent.t)

local t_assert = t.t_assert

local T_ASSERT_FORMAT = "Expected '%s' for '%s', got '%s'"

type table = {[any]: any}
type DataEnum = {
	FromValue: (self: DataEnum, value: number) -> EnumItem
} & Enum

export  type SerializedItem = {
	buf: buffer,
	instances: {Instance}?,
}

export type Schema<T> = {
	Type: string,

	Size: (number | (item: T) -> number)?,
	Validator: (...any) -> boolean,
	
	Write: (b: SerializedItem, offset: number, item: T) -> number,
	Read: (b: SerializedItem, offset: number) -> (T, number)
}

local WriteBufferRef: SerializedItem = {
	buf = WRITE_BUFFER,
	instances = {}
}

local SchemaValidator = t.interface {
	Type = t.string,
	
	Size = t.optional(t.union(t.number, t.callback)),
	Write = t.callback,
	Read = t.callback,
	
	Validator = t.callback
}

local SerializedItemValidator = t.interface {
	buf = t.buffer,
	instances = t.optional(t.array(t.Instance))
}

type SizeType =
	|	"u8"
|	"i8"
|	"u16"
|	"i16"
|	"u32"
|	"i32"
|	"f32"
|	"f64"

local FloatMuls: {[SizeType]: number} = {
	u8 = 1, i8 = 1,
	u16 = 10430.219195527361, i16 = 1,
	u32 = 683565275.41, i32 = 1, f32 = 1,
	f64 = 1
}

local Sizes: {[SizeType]: number} = {
	u8 = 1, i8 = 1,
	u16 = 2, i16 = 2,
	u32 = 4, i32 = 4, f32 = 4,
	f64 = 8
}

local SizeTypeMax = {
	u8 = 255, i8 = 127,
	u16 = 65535, i16 = 32767,
	u32 = 4294967295, i32 = 2147483647,
	f64 = math.huge
}

local SizeTypeMin = {
	u8 = 0, i8 = -128,
	u16 = 0, i16 = -32768,
	u32 = 0, i32 = -2147483648,
	f64 = -math.huge
}

local sin = math.sin
local sqrt = math.sqrt
local floor = math.floor
local min, max = math.min, math.max

local writeu8, readu8 = buffer.writeu8, buffer.readu8
local writei8, readi8 = buffer.writei8, buffer.readi8
local writeu16, readu16 = buffer.writeu16, buffer.readu16
local writei16, readi16 = buffer.writei16, buffer.readi16
local writeu32, readu32 = buffer.writeu32, buffer.readu32
local writei32, readi32 = buffer.writei32, buffer.readi32
local writef32, readf32 = buffer.writef32, buffer.readf32
local writef64, readf64 = buffer.writef64, buffer.readf64
local writestring, readstring = buffer.writestring, buffer.readstring
local len, copy = buffer.len, buffer.copy
local create = buffer.create

local Writers: {[SizeType]:(b: buffer, offset: number, v: number)->()} = {
	u8 = writeu8, i8 = writei8,
	u16 = writeu16, i16 = writei16,
	u32 = writeu32, i32 = writei32, f32 = writef32,
	f64 = writef64
}

local Readers: {[SizeType]:(b: buffer, offset: number)->number} = {
	u8 = readu8, i8 = readi8,
	u16 = readu16, i16 = readi16,
	u32 = readu32, i32 = readi32, f32 = readf32,
	f64 = readf64
}

local function copywritebuf(br: SerializedItem, offset: number, size: number)
	local b = br.buf
	local currentBufSize = len(b)
	if offset + size > currentBufSize then
		local newBuf = create(offset + size)
		
		if currentBufSize > 0 then
			copy(newBuf, 0, b, 0, currentBufSize)
		end
		
		br.buf = newBuf
	end
	
	copy(br.buf, offset, WRITE_BUFFER, offset, size)
	if #(WriteBufferRef.instances :: any) > 0 then
		br.instances = WriteBufferRef.instances
		WriteBufferRef.instances = {}
	end
end

local function expand(b: buffer, offset: number, by: number)
	local newsize = offset + by
	if newsize > buffer.len(b) then
		newsize //= 1/1.375
		
		local new = buffer.create(newsize)
		buffer.copy(new, 0, b)
		
		return new
	end
	
	return b
end

local function validateSizeType(s: SizeType)
	assert(
		s == "u8"
			or	s == "i8"
			or	s == "u16"
			or	s == "i16"
			or	s == "u32"
			or	s == "i32"
			or	s == "f32"
			or	s == "f64",
		`Expected SizeType, got {s}`
	)
end

local StaticSchemas = {
	empty = {
		Type = "nil",
		
		Size = 1,
		Write = function(_, offset) return offset + 1 end,
		Read = function(_, offset) return nil, offset + 1 end,
		
		Validator = t["nil"]
	} :: Schema<nil>,

	boolean = {
		Type = "boolean",
		
		Size = 1,
		Write = function(br, offset, v)
			local b = br.buf
			writeu8(b, offset, v and 1 or 0)
			return offset + 1
		end,
		Read = function(br, offset)
			local b = br.buf
			return readu8(b, offset) == 1, offset + 1
		end,
		
		Validator = t.boolean
	} :: Schema<boolean>,
}

local function numberSchema(s: SizeType)
	local write, read = Writers[s], Readers[s]
	local size = Sizes[s]
	local schema: Schema<number> = {
		Type = "number",
		
		Size = size,
		Write = function(br, offset, v)
			local b = br.buf
			write(b, offset, v)
			return offset + size
		end,
		Read = function(br, offset)
			local b = br.buf
			return read(b, offset), offset + size
		end,
		
		Validator = t.number
	}
	return function()
		return schema
	end
end

local function stringSchema(s: SizeType)
	local write, read = Writers[s], Readers[s]
	local size = Sizes[s]

	local schema: Schema<string> = {
		Type = "string",
		
		Size = function(item)
			return size + #item
		end,
		Write = function(br, offset, str)
			local b = br.buf
			local len = size + #str

			write(b, offset, #str)
			writestring(b, offset + size, str)

			return offset + size + #str
		end,
		Read = function(br, offset)
			local b = br.buf

			local len = read(b, offset)
			return readstring(b, offset + size, len), offset + size + len
		end,
		
		Validator = t.string
	}
	return function()
		return schema
	end
end

local function vectorSchema(s: SizeType)
	local write, read = Writers[s], Readers[s]
	local csize = Sizes[s]
	local size = csize * 3
	local schema: Schema<vector> = {
		Type = "vector",
		
		Size = size,
		Write = function(br, offset, v)
			local b = br.buf
			write(b, offset, v.x)
			write(b, offset + csize, v.y)
			write(b, offset + csize * 2, v.z)
			return offset + size
		end,
		Read = function(br, offset)
			local b = br.buf
			return vector.create(
				read(b, offset),
				read(b, offset + csize),
				read(b, offset + csize * 2)
			), offset + size
		end,
		
		Validator = t.vector
	}
	return function()
		return schema
	end
end

local function cframeSchema(posSizeType: SizeType, rotSizeType: SizeType)
	local posSize = Sizes[posSizeType]
	local rotSize = Sizes[rotSizeType]

	local o2 = posSize
	local o3 = posSize * 2
	
	local o4 = posSize * 3
	local o5 = o4 + rotSize
	local o6 = o5 + rotSize

	local size = o6 + rotSize

	local FLOAT_MUL = FloatMuls[rotSizeType]

	local posWrite, rotWrite = Writers[posSizeType], Writers[rotSizeType]
	local posRead, rotRead = Readers[posSizeType], Readers[rotSizeType]

	local schema: Schema<CFrame> = {
		Type = "CFrame",
		
		Size = size,
		Write = function(br, offset, c)
			local b = br.buf
			local rx, ry, rz = c:ToEulerAnglesXYZ()

			posWrite(b, offset, c.X)
			posWrite(b, offset + o2, c.Y)
			posWrite(b, offset + o3, c.Z)

			rotWrite(b, offset + o4, rx * FLOAT_MUL + 0.5)
			rotWrite(b, offset + o5, ry * FLOAT_MUL + 0.5)
			rotWrite(b, offset + o6, rz * FLOAT_MUL + 0.5)
			
			return offset + size
		end,
		Read = function(br, offset)
			local b = br.buf
			local x, y, z = posRead(b, offset), posRead(b, offset + o2), posRead(b, offset + o3)
			local rx, ry, rz = rotRead(b, offset + o4) / FLOAT_MUL, rotRead(b, offset + o5) / FLOAT_MUL, rotRead(b, offset + o6) / FLOAT_MUL

			return CFrame.fromEulerAnglesXYZ(rx, ry, rz) + Vector3.new(x, y, z), offset + size
		end,
		
		Validator = t.CFrame
	}
	return function()
		return schema
	end
end

local function arraySchema(s: SizeType)
	return function<T>(valueSchema: Schema<T>): Schema<{T}>
		local write, read = valueSchema.Write, valueSchema.Read
		local lenwrite, lenread = Writers[s], Readers[s]

		local schema: Schema<{T}> = {
			Type = "array",
			
			Write = function(br, offset, t)
				if #t == 0 then return offset end
				local tlen = #t

				local originalOffset = offset
				lenwrite(WRITE_BUFFER, offset, tlen)
				offset += Sizes[s]

				for i, v in t do
					offset = write(WriteBufferRef, offset, v)
				end
				
				local size = offset - originalOffset
				copywritebuf(br, originalOffset, size)

				return offset
			end,
			Read = function(br, offset)
				local b = br.buf
				local tlen = lenread(b, offset)
				offset += Sizes[s]

				local t = table.create(tlen)

				for i = 1, tlen do
					t[i], offset = read(br, offset)
				end

				return t, offset
			end,
			
			Validator = t.array(valueSchema.Validator)
		}

		return schema
	end
end

local function dictionarySchema(s: SizeType)
	return function<K, V>(keySchema: Schema<K>, valueSchema: Schema<V>): Schema<{[K]: V}>
		local keyWrite, keyRead = keySchema.Write, keySchema.Read
		local valueWrite, valueRead = valueSchema.Write, valueSchema.Read
		local lenWrite, lenRead = Writers[s], Readers[s]
		local lenSize = Sizes[s]

		local schema: Schema<{[K]: V}> = {
			Type = "dictionary",

			Size = function(dict)
				local count = 0
				local totalSize = lenSize -- Size for count

				for key, value in dict do
					count += 1

					-- Add key size
					if keySchema.Size then
						if type(keySchema.Size) == "number" then
							totalSize += keySchema.Size
						else
							totalSize += (keySchema.Size :: any)(key)
						end
					end

					-- Add value size
					if valueSchema.Size then
						if type(valueSchema.Size) == "number" then
							totalSize += valueSchema.Size
						else
							totalSize += (valueSchema.Size :: any)(value)
						end
					end
				end

				return totalSize
			end,

			Write = function(br, offset, dict)
				local originalOffset = offset
				local count = 0

				-- Count entries first
				for _ in dict do
					count += 1
				end

				-- Write count
				lenWrite(WRITE_BUFFER, offset, count)
				offset += lenSize

				-- Write key-value pairs
				for key, value in dict do
					offset = keyWrite(WriteBufferRef, offset, key)
					offset = valueWrite(WriteBufferRef, offset, value)
				end

				local size = offset - originalOffset
				copywritebuf(br, originalOffset, size)

				return offset
			end,

			Read = function(br, offset)
				local b = br.buf
				local count = lenRead(b, offset)
				offset += lenSize

				local dict = {}

				for i = 1, count do
					local key, newOffset = keyRead(br, offset)
					local value, finalOffset = valueRead(br, newOffset)
					dict[key] = value
					offset = finalOffset
				end

				return dict, offset
			end,

			Validator = function(value)
				if type(value) ~= "table" then
					return false
				end

				for key, val in value do
					if not keySchema.Validator(key) then
						return false
					end
					if not valueSchema.Validator(val) then
						return false
					end
				end

				return true
			end
		}

		return schema
	end
end

local function structSchema(isTuple: boolean)
	return function<T>(structure: T): Schema<T>
		t_assert("structure", structure, "table")
		if isTuple then
			t_assert("structure", structure, t.map(t.number, t.any))
		else
			t_assert("structure", structure, t.map(t.string, t.any))
		end
		
		local schemas: {Schema<any>} = {}
		local indexToName = {}
		
		local structure = structure :: any
		local validatorInterface = {}
		local keys = {}
		
		for key, value in structure do
			table.insert(keys, key)
			validatorInterface[key] = value.Validator
		end
		for i, key in keys do
			indexToName[i] = key
		end

		table.sort(indexToName)
		for i, key in indexToName do
			local schema = structure[key]
			if not schema then
				error(`Invalid field type for key {key}`)
			end
			schemas[i] = schema :: Schema<any>
		end

		local schema: Schema<T> = {
			Type = isTuple and "tuple" or "struct",
			
			Write = function(br, offset, item)
				if type(item) ~= "table" then
					error(`Table expected, got {item}`)
				end
				local originalOffset = offset
				for i, serde in schemas do
					offset = serde.Write(WriteBufferRef, offset, item[indexToName[i]])
				end
				local size = offset - originalOffset

				copywritebuf(br, originalOffset, size)
				
				return offset
			end,
			Read = function(br, offset)
				local result = {}
				
				for i, serde in schemas do
					local item, newOffset = serde.Read(br, offset)
					result[indexToName[i]] = item
					offset = newOffset
				end
				return result::any, offset
			end,
			
			Validator = t.interface(validatorInterface)
		}

		return schema
	end
end

local function enumSchema(s: SizeType)
	return function(enum: DataEnum): Schema<EnumItem>
		local schema: Schema<EnumItem> = {
			Type = "EnumItem",
			
			Size = Sizes[s],
			Write = function(br, offset, item)
				local b = br.buf
				Writers[s](b, offset, item.Value)
				return offset + Sizes[s]
			end,
			Read = function(br, offset)
				local b = br.buf
				return enum:FromValue( Readers[s](b, offset) ), offset + Sizes[s]
			end,
			
			Validator = t.enum(enum)
		}

		return schema
	end
end

local function unionSchema(s: SizeType)
	return function(...: Schema<any>): Schema<any>
		local unions = {...}
		local len = #unions

		local ChoiceReaders = table.create(len)
		local ChoiceWriters = {}
		local Validators = {}

		for i, union in unions do
			ChoiceReaders[i] = union
			ChoiceWriters[union.Type] = union
			table.insert(Validators, union.Validator)
		end

		local schema: Schema<any> = {
			Type = "union",
			
			Size = function(item)
				local vtype = extypeof(item)
				
				local choice = ChoiceWriters[vtype]
				assert(choice ~= nil, `Unincluded datatype in union: {vtype}`)
				if not choice.Size then
					return 1
				end
				if type(choice.Size) == "number" then
					return choice.Size + Sizes[s]
				else
					return (choice.Size :: any)(item) + Sizes[s]
				end
			end,
			Write = function(br, offset, item)
				local vtype = extypeof(item)
				
				local choice = ChoiceWriters[vtype]
				assert(choice ~= nil, `Unincluded datatype in union: {vtype}`)
				local idx = table.find(ChoiceReaders, choice)
				assert(idx ~= nil, "Invalid union choice")

				Writers[s](WRITE_BUFFER, offset, idx)
				local newOffset = choice.Write(WriteBufferRef, offset + Sizes[s], item)
				
				local size = newOffset - offset
				copywritebuf(br, offset, size)
				
				return newOffset
			end,
			Read = function(br, offset)
				local b = br.buf
				
				local choice = Readers[s](b, offset)
				local result, newOffset = ChoiceReaders[choice].Read(br, offset + Sizes[s])
				return result, newOffset
			end,
			
			Validator = t.unionList(Validators)
		}

		return schema
	end
end

local function instanceRefSchema()
	return function(className: string?): Schema<Instance>
		return {
			Type = "Instance",
			
			Size = 4,
			Write = function(br, offset, item)
				local b = br.buf
				local instances = br.instances :: any
				if not instances then
					instances = {}
					br.instances = instances
				end
				
				writeu32(b, offset, #instances + 1)
				table.insert(instances, item)
				
				return offset + 4
			end,
			Read = function(br, offset)
				local b = br.buf
				local instances = br.instances :: any
				if not instances then
					instances = {}
					br.instances = instances
				end
				
				local idx = readu32(b, offset)
				return instances[idx], offset + 4
			end,
			
			Validator = className and t.instance(className) or t.Instance
		}
	end
end

local u8union = unionSchema("u8")
local function optionalSchema()
	return function<T>(schema: Schema<T>): Schema<T?>
		return u8union(StaticSchemas.empty, schema)
	end
end

return {
	SchemaValidator = SchemaValidator,
	SerializedItemValidator = SerializedItemValidator,
	
	data = {
		empty = function()
			return StaticSchemas.empty
		end,
		boolean = function()
			return StaticSchemas.boolean
		end,
		
		str_u8 = stringSchema("u8"),
		str_u16 = stringSchema("u16"),
		str_u32 = stringSchema("u32"),
		str_f64 = stringSchema("f64"),

		u8 = numberSchema("u8"),
		i8 = numberSchema("i8"),
		u16 = numberSchema("u16"),
		i16 = numberSchema("i16"),
		u32 = numberSchema("u32"),
		i32 = numberSchema("i32"),
		f32 = numberSchema("f32"),
		f64 =  numberSchema("f64"),

		vec_u8 = vectorSchema("u8"),
		vec_i8 = vectorSchema("i8"),
		vec_u16 = vectorSchema("u16"),
		vec_i16 = vectorSchema("i16"),
		vec_u32 = vectorSchema("u32"),
		vec_i32 = vectorSchema("i32"),
		vec_f32 = vectorSchema("f32"),
		vec_f64 = vectorSchema("f64"),

		arr_8 = arraySchema("u8"),
		arr_16 = arraySchema("u16"),
		arr_32 = arraySchema("u32"),
		arr_64 = arraySchema("f64"),
		
		dict_8 = dictionarySchema("u8"),
		dict_16 = dictionarySchema("u16"),
		dict_32 = dictionarySchema("u32"),
		dict_64 = dictionarySchema("f64"),
		
		cframe_f32_u16 = cframeSchema("f32", "u16"),
		cframe_f32_u32 = cframeSchema("f32", "u32"),
		cframe_f32_f32 = cframeSchema("f32", "f32"),
		cframe_f32_f64 = cframeSchema("f32", "f64"),
		cframe_f64_u16 = cframeSchema("f64", "u16"),
		cframe_f64_u32 = cframeSchema("f64", "u32"),
		cframe_f64_f32 = cframeSchema("f64", "f32"),
		cframe_f64_f64 = cframeSchema("f64", "f64"),

		struct = structSchema(false),
		tuple = structSchema(true),

		enum_u8 = enumSchema("u8"),
		enum_u16 = enumSchema("u16"),
		enum_u32 = enumSchema("u32"),

		union_u8 = u8union,
		union_u16 = unionSchema("u16"),
		union_u32 = unionSchema("u32"),

		optional = optionalSchema(),

		inst_ref = instanceRefSchema(),
		
		--table = tableSchema()
	},
	constructors = {
		stringSchema = stringSchema,
		numberSchema = numberSchema,
		vectorSchema = vectorSchema,
		cframeSchema = cframeSchema,
		arraySchema = arraySchema
	}
}