-- MIT License
--
-- Copyright (c) 2026 Kevin Krol
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

if LibStub == nil then
	error("LibLog-1.0 requires LibStub")
end

--- @class LibLog-1.0.LogMessage
--- @field public message string The human-readable log string.
--- @field public template string The unprocessed message template.
--- @field public level LibLog-1.0.LogLevel The (numeric) level of the log. Can be compared against `LibLog.LogLevel`, or stringified using `LibLog.labels`.
--- @field public addon? string The name of the source addon.
--- @field public time integer The number of seconds that have elapsed since the Unix epoch.
--- @field public sequenceId integer The unique sequence identifier of the log within the current second.
--- @field public properties table<string, unknown> All properties that have been extracted from the template string or manually injected.

--- @class LibLog-1.0.Sink
--- @field public OnLogMessageReceived fun(message: LibLog-1.0.LogMessage)

--- @class LibLog-1.0.SinkConfiguration
--- @field public callback fun(message: LibLog-1.0.LogMessage)
--- @field public obj? table
--- @field public enabled boolean

--- @class LibLog-1.0.MessageTemplate
--- @field public format string A string containing % style placeholders such as %d, %.2f, etc. Can be used to format the message.
--- @field public stringFormat string A string containing %s placeholders for each property. Can be used to format the message.
--- @field public properties LibLog-1.0.MessageTemplateProperty[]

--- @class LibLog-1.0.MessageTemplateProperty
--- @field public name string The name of the property, which can be used to reference a field in the log message or log message properties.
--- @field public format string The format of the property, such as %d, %.2f, %s, etc. Can be used to format the property value.
--- @field public replacer? string The name of the replacement table to use when formatting this property, which can be used to convert enum values into human-readable strings.

--- @class LibLog-1.0.Property
--- @field public name string
--- @field public value unknown
--- @field public isCallback boolean

--- @class LibLog-1.0
--- @field private embeds table<LibLog-1.0.Logger, boolean>
--- @field private levels table<string, LibLog-1.0.LogLevel>
--- @field private enumNames table<unknown, string>
--- @field private sinks table<string, LibLog-1.0.SinkConfiguration>
--- @field private currentTime integer
--- @field private currentSequenceId integer
local LibLog = LibStub:NewLibrary("LibLog-1.0", 17)
if LibLog == nil then
	return
end

--- @enum LibLog-1.0.LogLevel
LibLog.LogLevel = {
	NONE = 0,
	VERBOSE = 1, -- High-frequency, noisy data that is rarely enabled outside of debugging.
	DEBUG = 2, -- Code paths and state changes that are useful when determining how something happened.
	INFO = 3, -- General status updates and runtime milestones.
	WARNING = 4, -- User-error, or other non-breaking issues.
	ERROR = 5, -- A high-severity logic issue that leaves functionality unavailable or expections broken.
	FATAL = 6 -- A critical or otherwise unrecoverable error that must halt execution.
}

LibLog.labels = {
	[LibLog.LogLevel.VERBOSE] = "VRB",
	[LibLog.LogLevel.DEBUG] = "DBG",
	[LibLog.LogLevel.INFO] = "INF",
	[LibLog.LogLevel.WARNING] = "WRN",
	[LibLog.LogLevel.ERROR] = "ERR",
	[LibLog.LogLevel.FATAL] = "FTL"
}

LibLog.configKey = "logLevel"

LibLog.embeds = LibLog.embeds or {}
LibLog.levels = LibLog.levels or {}
LibLog.enumNames = {}
LibLog.sinks = LibLog.sinks or {}
LibLog.currentTime = LibLog.currentTime or 0
LibLog.currentSequenceId = LibLog.currentSequenceId or 1

--- @class LibLog-1.0.ChatFrameSink : LibLog-1.0.Sink
local ChatFrameSink = {}

--- @type table<string, string>
ChatFrameSink.COLOR_SCHEME = {
	[LibLog.LogLevel.VERBOSE] = "ff6e6e6e",
	[LibLog.LogLevel.DEBUG] = "ffa1a1a1",
	[LibLog.LogLevel.INFO] = "ff00dfff",
	[LibLog.LogLevel.WARNING] = "ffffcf40",
	[LibLog.LogLevel.ERROR] = "ffff5f5f",
	[LibLog.LogLevel.FATAL] = "ffff0000",
	["table"] = "ff808080",
	["tableKey"] = "ffffa64d",
	["string"] = "fffff9b0",
	["number"] = "ff38ff70",
	["boolean"] = "ff99ff00",
	["nil"] = "ffff77ff",
	["event"] = "ffbd93f9",
}

--- @class LibLog-1.0.Logger
--- @field public name? string
--- @field public moduleName? string
--- @field public logProperties? table<string, LibLog-1.0.Property>
local Logger = {}

local L = {
	level = "Log level",
	level_desc = "Select the logging level for this addon. Select 'NONE' to completely disable logging.\n\nLower values mean more messages get logged, where 'VERBOSE' logs everything."
}

--- @type LibLog-1.0.LogLevel
local minLogLevel = LibLog.LogLevel.INFO

--- @type table<string, LibLog-1.0.MessageTemplate>
local templateCache = {}

--- @type table<table, boolean>
local tableCache = {}

--- @param err any
--- @return function
local function ErrorHandler(err)
	return geterrorhandler()(err)
end

local function AcquireCachedTable()
	local result = next(tableCache)

	if result ~= nil then
		tableCache[result] = nil
		return result
	end

	return {}
end

--- @param tbl table
local function ReleaseCachedTable(tbl)
	for k in pairs(tbl) do
		tbl[k] = nil
	end

	tableCache[tbl] = true
end

--- @generic T
--- @param value T
--- @param seen? table<T, T>
--- @return T
local function DeepCopy(value, seen)
	if type(value) ~= "table" then
		return value
	end

	if value.GetObjectType ~= nil then
		return tostring(value)
	end

	local root = seen == nil
	seen = seen or AcquireCachedTable()

	if seen[value] then
		return seen[value]
	end

	local result = {}
	seen[value] = result

	for k, v in pairs(value) do
		local copyK = DeepCopy(k, seen)
		local copyV = DeepCopy(v, seen)
		result[copyK] = copyV
	end

	if root then
		ReleaseCachedTable(seen)
	end

	return result
end

--- @param logger LibLog-1.0.Logger
local function GetLoggerName(logger)
	if logger.moduleName ~= nil and logger.name ~= nil then
		local realName = string.gsub(logger.name, "_" .. logger.moduleName .. "$", "")
		return realName, logger.moduleName
	end

	return logger.name
end

local function GetReplacerName(logger, id)
	local name = GetLoggerName(logger)
	return (name or "") .. "_" .. id
end

--- @param logger LibLog-1.0.Logger
--- @param template LibLog-1.0.MessageTemplate
--- @param values unknown[]
--- @return string
local function CreateMessage(logger, template, values)
	--- @param property LibLog-1.0.MessageTemplateProperty
	--- @param current unknown
	--- @param visited table<table, boolean>
	--- @param escape? boolean
	--- @return string
	local function Serialize(property, current, visited, escape)
		if type(current) == "table" then
			if visited[current] then
				return "<circular reference>"
			end

			local result = AcquireCachedTable()
			table.insert(result, "{")

			visited[current] = true

			for k, v in pairs(current) do
				table.insert(result, type(k) == "string" and k or "[" .. tostring(k) .. "]")
				table.insert(result, "=")
				table.insert(result, Serialize(property, v, visited, true) .. ",")
			end

			visited[current] = false

			table.insert(result, "}")

			current = table.concat(result, " ")
			ReleaseCachedTable(result)

			return current
		elseif escape and type(current) == "string" then
			return string.format("%q", current)
		end

		if property.replacer ~= nil then
			local id = GetReplacerName(logger, property.replacer)

			if LibLog.enumNames[id] ~= nil then
				local enumValue = LibLog.enumNames[id][current]

				if enumValue ~= nil then
					return enumValue
				end
			end
		end

		return tostring(current)
	end

	local result = AcquireCachedTable()
	local visited = AcquireCachedTable()

	for i = 1, #template.properties do
		result[i] = Serialize(template.properties[i], values[i], visited)
	end

	local message = string.format(template.format, unpack(result))

	ReleaseCachedTable(visited)
	ReleaseCachedTable(result)

	return message
end

--- @param template string
--- @return LibLog-1.0.MessageTemplate
local function GetMessageTemplate(template)
	local result = templateCache[template]
	if result ~= nil then
		return result
	end

	--- @type LibLog-1.0.MessageTemplate
	result = {
		format = "",
		stringFormat = "",
		properties = {}
	}

	template = string.gsub(template, "%%", "%%%%")

	result.format = string.gsub(template, "{(%w+)#?(%w*):?(.-)}", function(key, replacer, format)
		--- @type LibLog-1.0.MessageTemplateProperty
		local item = {
			name = key,
			format = format ~= "" and ("%" .. format) or "%s",
			replacer = replacer ~= "" and replacer or nil
		}

		table.insert(result.properties, item)
		return item.format
	end)

	result.stringFormat = string.gsub(template, "{(.-)}", "%%s")

	templateCache[template] = result

	return result
end

--- @param ... unknown
--- @return integer
--- @return unknown[]
local function PackVarargs(...)
	local count = select("#", ...)
	local result = AcquireCachedTable()

	for i = 1, count do
		local value = select(i, ...)
		result[i] = DeepCopy(value)
	end

	return count, result
end

--- @param ... unknown
--- @return integer
--- @return unknown[]
local function GetValues(...)
	local n = select("#", ...)
	if n ~= 1 then
		return PackVarargs(...)
	end

	local func = select(1, ...)
	if type(func) ~= "function" then
		return PackVarargs(...)
	end

	local count, callback = PackVarargs(xpcall(func, ErrorHandler))

	if callback[1] then
		table.remove(callback, 1)
		return count - 1, callback
	end

	return 0, AcquireCachedTable()
end

--- @param logger LibLog-1.0.Logger
--- @param template LibLog-1.0.MessageTemplate
--- @param values unknown[]
--- @return table<string, unknown>
local function PopulateMessageProperties(logger, template, values)
	local name = GetLoggerName(logger)

	--- @type table<string, unknown>
	local result = {}

	if logger.logProperties ~= nil then
		for _, v in pairs(logger.logProperties) do
			if v.isCallback then
				local success, value = xpcall(v.value, ErrorHandler)

				if success then
					result[v.name] = DeepCopy(value)
				end
			else
				result[v.name] = DeepCopy(v.value)
			end
		end
	end

	for i = 1, #template.properties do
		local property = template.properties[i]
		result[property.name] = values[i]

		if property.replacer ~= nil then
			local id = GetReplacerName(logger, property.replacer)

			if LibLog.enumNames[id] ~= nil then
				local enumValue = LibLog.enumNames[id][values[i]]

				if enumValue ~= nil then
					result[property.name] = enumValue
				end
			end
		end
	end

	return result
end

--- @param name? string
--- @param level LibLog-1.0.LogLevel
--- @return boolean
local function IsLogLevelEnabled(name, level)
	if name ~= nil then
		local addonLevel = LibLog.levels[name]

		if addonLevel ~= nil then
			return level >= addonLevel
		end
	end

	return level >= minLogLevel
end

--- @param message LibLog-1.0.LogMessage
function ChatFrameSink:OnLogMessageReceived(message)
	local frame = DEFAULT_CHAT_FRAME

	--- @type string[]
	local prefix
	local color = self.COLOR_SCHEME[message.level]
	local addon = message.addon or ""

	if message.level <= LibLog.LogLevel.DEBUG then
		local time = date("%H:%M:%S", message.time) --[[@as string]]
		prefix = { "|c", color, time, " ", LibLog.labels[message.level], " ", addon, ":", "|r" }
	elseif message.level == LibLog.LogLevel.INFO then
		prefix = { "|c", color, addon, ":", "|r" }
	else
		prefix = { "|c", color, LibLog.labels[message.level], " ", addon, ":", "|r" }
	end

	if frame then
		frame:AddMessage(table.concat(prefix, "") .. " " .. self:CreateMessage(message))
	end
end

--- @param message LibLog-1.0.LogMessage
function ChatFrameSink:CreateMessage(message)
	local template = LibLog:GetFormat(message.template)
	local values = AcquireCachedTable()

	for i = 1, #template.properties do
		local property = template.properties[i]
		values[i] = self:Serialize(message, property)
	end

	local result = string.format(template.stringFormat, unpack(values))
	ReleaseCachedTable(values)

	return result
end

--- @private
--- @param message LibLog-1.0.LogMessage
--- @param property LibLog-1.0.MessageTemplateProperty
--- @return string
function ChatFrameSink:Serialize(message, property)
	local TABLE_COLOR = self.COLOR_SCHEME["table"]
	local TABLE_KEY_COLOR = self.COLOR_SCHEME["tableKey"]
	local STRING_COLOR = self.COLOR_SCHEME["string"]

	--- @param current unknown
	--- @param visited table<table, boolean>
	--- @param escape? boolean
	--- @return string
	local function Serialize(current, visited, escape)
		local valueType = type(current)
		local color = valueType --[[@as string]]

		if valueType == "table" then
			if visited[current] then
				return self:Colorize("<circular reference>", TABLE_COLOR)
			end

			local result = AcquireCachedTable()
			table.insert(result, self:Colorize("{", TABLE_COLOR))

			visited[current] = true

			for k, v in pairs(current) do
				table.insert(result, self:Colorize(type(k) == "string" and k or "[" .. tostring(k) .. "]", TABLE_KEY_COLOR))
				table.insert(result, self:Colorize("=", TABLE_COLOR))
				table.insert(result, Serialize(v, visited, true) .. ",")
			end

			visited[current] = false

			table.insert(result, self:Colorize("}", TABLE_COLOR))

			current = table.concat(result, " ")
			ReleaseCachedTable(result)
		elseif valueType == "string" then
			if escape then
				current = string.format("%q", current)
			end

			if C_EventUtils.IsEventValid(current) then
				color = "event"
			end
		else
			current = tostring(current)
		end

		return self:Colorize(string.format(property.format, current), self.COLOR_SCHEME[color] or STRING_COLOR)
	end

	local visited = AcquireCachedTable()
	local result = Serialize(message[property.name] or message.properties[property.name], visited)

	ReleaseCachedTable(visited)

	return result
end

--- @private
--- @param string string
--- @param color string
--- @return string
function ChatFrameSink:Colorize(string, color)
	return "|c" .. color .. string .. "|r"
end

--- Log a VRB message. Verbose logs should be used for high-frequency logs or low-level data. For example, raw calculations or other raw data.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogVerbose(template, ...)` to immediately exit the running function with a `nil`
--- value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogVerbose(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.VERBOSE, template, ...)
end

--- Log a DBG message. Debug logs should be used for developers to verify code paths, state changes, or event registration during active
--- development and testing.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogDebug(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogDebug(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.DEBUG, template, ...)
end

--- Log an INF message. Info logs shoud be used for general status updates and milestones. Generally when following the happy path of your code
--- to indicate the addon is working. For example, successful loading, profile changes, or user-triggered actions.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogInfo(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogInfo(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.INFO, template, ...)
end

--- Log a WRN message. Warning logs should be the result of user error or other non-breaking issues. For example, optional settings are missing
--- or an input is invalid.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogWarning(template, ...)` to immediately exit the running function with a `nil`
--- value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogWarning(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.WARNING, template, ...)
end

--- Log an ERR message. Error logs should indicate a high severity logic failure. For example, an API returns unexpected data. An error likely
--- indicates a bug that should be fixed, though execution can continue.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogError(template, ...)` to immediately exit the running function with a `nil` value.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogError(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.ERROR, template, ...)
end

--- Log a FTL message, and submit the error to the error handler. Fatal logs are the highest severity, and should be used sparringly, when
--- execution **cannot** continue and must be halted because continuing may lead to data corruption or unrecoverable states. For example, misssing libraries
--- or broken saved variables.
---
--- This function returns an `unknown` value to allow for `return MyAddon:LogFatal(template, ...)` to immediately exit the running function. Though this
--- function will trigger a Lua error pop-up when enabled by the user.
---
--- @param template string The template message, use `{propertyName}` to enable parameter replacements.
--- @param ... any The values to log.
--- @return unknown
function Logger:LogFatal(template, ...)
	return LibLog:Log(self, LibLog.LogLevel.FATAL, template, ...)
end

--- Push a new property onto the stack, the value of this property will be present within the context of all further logs coming from this logger, until it is
--- popped.
---
--- @param name string
--- @param value unknown|function
function Logger:PushLogProperty(name, value)
	--- @type LibLog-1.0.Property
	local property = {
		name = name,
		value = value,
		isCallback = type(value) == "function"
	}

	self.logProperties = self.logProperties or {}
	self.logProperties[name] = property
end

--- Pop properties that were previously pushed.
---
--- @param ... string
function Logger:PopLogProperty(...)
	if self.logProperties == nil then
		return
	end

	local n = select("#", ...)
	for i = 1, n do
		local name = select(i, ...)
		self.logProperties[name] = nil
	end
end

--- Create a closure where all logs contain the given properties. This is useful when you don't want to deal with popping properties manually, as that can be
--- error-prone.
---
--- @param properties table<string, unknown>
--- @param closure fun(logger: LibLog-1.0.Logger)
function Logger:WithLogContext(properties, closure)
	local logger = self:ForLogContext(properties)

	local ok, err = pcall(closure, logger)

	if not ok then
		error(err, 2)
	end
end

--- Create a new logger with the specified context. All logs produced by this logger will have additional properties added to them.
---
--- @param properties? table<string, unknown>
--- @return LibLog-1.0.Logger
function Logger:ForLogContext(properties)
	--- @type table<string, LibLog-1.0.Property>
	local props

	if properties ~= nil then
		props = {}

		for k, v in pairs(properties) do
			--- @type LibLog-1.0.Property
			local property = {
				name = k,
				value = v,
				isCallback = type(v) == "function"
			}

			props[k] = property
		end
	else
		props = DeepCopy(self.logProperties) or {}
	end

	if self.logProperties ~= nil then
		for k, v in pairs(self.logProperties) do
			if props[k] == nil then
				props[k] = v
			end
		end
	end

	local proxy = {
		logProperties = props,
		_parent = self
	}

	setmetatable(proxy, {
		__index = function(tbl, key)
			return tbl._parent[key]
		end
	})

	return proxy --[[@as LibLog-1.0.Logger]]
end

--- Add an enum-like type to the logger, which can be referenced within log templates using `{propertyName#EnumName}`.
---
--- @param id string
--- @param enum table<string, unknown>
function Logger:AddLogEnum(id, enum)
	id = GetReplacerName(self, id)

	LibLog.enumNames[id] = {}
	for k, v in pairs(enum) do
		LibLog.enumNames[id][v] = k
	end
end

--- Check if the given log level is currently enabled.
---
--- This will always return `true` for the FTL log level.
---
--- @param level LibLog-1.0.LogLevel|string
--- @return boolean
function Logger:IsLogLevelEnabled(level)
	local name = GetLoggerName(self)

	if type(level) == "string" then
		level = LibLog.LogLevel[level:upper()]
	end

	if not IsLogLevelEnabled(name, level) then
		return level >= LibLog.LogLevel.FATAL
	end

	return true
end

--- Set the minimum log level, any logs with a level lower than the given value will be ignored.
---
--- @param level? LibLog-1.0.LogLevel|string The log level to set.
function Logger:SetLogLevel(level)
	local name = GetLoggerName(self)
	if name == nil then
		return
	end

	if type(level) == "string" then
		level = LibLog.LogLevel[level:upper()]
	end

	LibLog.levels[name] = level
end

--- Set the log level using a configuration table.
---
--- @param configTable table A configuration table to retrieve the current log level from, usually your saved variables.
function Logger:SetLogLevelFromConfigTable(configTable)
	local name = GetLoggerName(self)
	if name == nil then
		return
	end

	local level = configTable[LibLog.configKey]

	if level ~= nil then
		self:SetLogLevel(level)
	end
end

--- Get the current log level.
---
--- @return LibLog-1.0.LogLevel
function Logger:GetLogLevel()
	local name = GetLoggerName(self)

	if name == nil then
		return minLogLevel
	end

	return LibLog.levels[name] or minLogLevel
end

--- Create an AceGUI option table which can manipulate the log level.
---
--- @param configTable table A configuration table to store and retrieve current log level values from, usually your saved variables.
function Logger:GetLogLevelOptionObject(configTable)
	return {
		name = L.level,
		desc = L.level_desc,
		type = "select",
		style = "dropdown",
		values = function()
			local result = {}

			for k, v in pairs(LibLog.LogLevel) do
				result[v] = k
			end

			return result
		end,
		sorting = function()
			local result = {}

			for _, v in pairs(LibLog.LogLevel) do
				table.insert(result, v)
			end

			table.sort(result, function(l, r)
				return l < r
			end)

			return result
		end,
		get = function()
			return configTable[LibLog.configKey] or self:GetLogLevel()
		end,
		set = function(_, value)
			self:SetLogLevel(value)
			configTable[LibLog.configKey] = value
		end
	}
end

--- Register an external sink to replicate the logging stream.
---
--- @param name string
--- @param callback fun(message: LibLog-1.0.LogMessage)|LibLog-1.0.Sink
function LibLog:RegisterSink(name, callback)
	if type(callback) == "function" then
		self.sinks[name] = {
			callback = callback,
			enabled = true
		}
	elseif type(callback) == "table" then
		assert(type(callback.OnLogMessageReceived) == "function", "Cannot register a sink without an OnLogMessageReceived function")

		self.sinks[name] = {
			callback = callback.OnLogMessageReceived,
			obj = callback,
			enabled = true
		}
	else
		error("Cannot register a sink that is not a function, or a table containing an 'OnLogMessageReceived' function")
	end
end

--- Enable a sink.
---
--- @param name string
function LibLog:EnableSink(name)
	local sink = self.sinks[name]

	if sink ~= nil then
		sink.enabled = true
	end
end

--- Disable a sink, preventing it from receiving new messages until re-enabled.
---
--- @param name string
function LibLog:DisableSink(name)
	local sink = self.sinks[name]

	if sink ~= nil then
		sink.enabled = false
	end
end

--- Get all registered, or all enabled sinks.
---
--- @param enabledOnly? boolean
--- @return string[]
function LibLog:GetSinks(enabledOnly)
	--- @type string[]
	local result = {}

	for name, sink in pairs(self.sinks) do
		if not enabledOnly or (enabledOnly and sink.enabled) then
			table.insert(result, name)
		end
	end

	return result
end

--- Embed `LibLog-1.0` into the target object, making several logging functions available for use.
---
--- @generic T : table
--- @param target T The target object.
--- @return T
function LibLog:Embed(target)
	for k, v in pairs(Logger) do
		target[k] = v
	end

	self.embeds[target] = true

	return target
end

--- @param template string
--- @return LibLog-1.0.MessageTemplate
function LibLog:GetFormat(template)
	return GetMessageTemplate(template)
end

--- Get the next sequence ID for the current time and advance the internal sequence counter.
---
--- @return number time
--- @return integer sequenceId
function LibLog:GetNextSequenceId()
	local now = time()

	if now ~= self.currentTime then
		self.currentTime = now
		self.currentSequenceId = 1
	else
		self.currentSequenceId = self.currentSequenceId + 1
	end

	return self.currentTime, self.currentSequenceId
end

--- @private
--- @param logger LibLog-1.0.Logger The source logger.
--- @param level LibLog-1.0.LogLevel The log level to log with.
--- @param template string The message template.
--- @param ... any The values to log.
--- @return unknown
function LibLog:Log(logger, level, template, ...)
	local name, module = GetLoggerName(logger)
	local isAllowed = IsLogLevelEnabled(name, level)
	local isFatal = level == self.LogLevel.FATAL

	if not isAllowed and not isFatal then
		return nil
	end

	local templateObj = GetMessageTemplate(template)
	local _, values = GetValues(...)
	local message = CreateMessage(logger, templateObj, values)

	if isAllowed then
		local time, sequenceId = self:GetNextSequenceId()

		--- @type LibLog-1.0.LogMessage
		local result = {
			message = message,
			template = template,
			addon = name,
			module = module,
			level = level,
			time = time,
			sequenceId = sequenceId,
			properties = PopulateMessageProperties(logger, templateObj, values)
		}

		for _, sink in pairs(self.sinks) do
			if sink.enabled then
				if sink.obj ~= nil then
					xpcall(sink.callback, ErrorHandler, sink.obj, result)
				else
					xpcall(sink.callback, ErrorHandler, result)
				end
			end
		end
	end

	ReleaseCachedTable(values)

	if isFatal then
		error(message, 3)
	end

	return nil
end

--- @private
function LibLog:TestSuite()
	--- @type LibLog-1.0.Logger
	local Addon = LibLog:Embed({
		name = "TestSuite"
	})

	Addon:SetLogLevel(self.LogLevel.INFO)
	Addon:LogVerbose("HIDDEN: Verbose")
	Addon:LogDebug("HIDDEN: Debug")
	Addon:LogInfo("VISIBLE: Info")
	Addon:LogWarning("VISIBLE: Warning")

	Addon:LogInfo("string={stringValue}, number={numberValue}, boolean={booleanValue}, nil={nilValue}, plain text", "string", 123.456, true, nil)
	Addon:LogInfo("Complex: {complexTable}", {
		sub = { a = 1, b = { "deep" } },
		empty = {},
		list = { 10, nil, 30 }
	})
	Addon:LogInfo("Empty Top-Level: {emptyTable}", {})

	local circular = { name = "Self" }
	circular.child = circular
	Addon:LogInfo("Circular: {circularTable}", circular)

	local sameTableRef = { name = "Self" }
	Addon:LogInfo("References the same table: {sameTableRef}", { t1 = sameTableRef, t2 = sameTableRef })

	Addon:LogInfo("Deep: {deepTable}", { two = { three = { four = { five = { six = { "test" }}}}}})

	Addon:LogInfo("{player} is {online} with {hp} HP", "Arthas", true, 50.5)
	Addon:LogInfo("With more parameters than arguments: {player} is {online} with {hp} HP", "Arthas")
	Addon:LogInfo("With more arguments than parameters: {player} is {online} with {hp} HP", "Arthas", true, 50.5, "extra", 0.2, true)

	Addon:LogInfo("{cpu} at {time}", function()
		return "0.01ms", GetTime()
	end)

	Addon:PushLogProperty("preContext", "pushed before starting the context")
	Addon:WithLogContext({additional = "context", some = 1, more = true, context = { 1, 3, 5 }}, function(logger)
		logger:LogInfo("Using WithLogContext")

		logger:LogInfo("Using WithLogContext and specifying more arguments: {player}", "Arthas")

		logger:LogInfo("Using WithContext and overriding properties: {some}", "overriden")
	end)
	Addon:PopLogProperty("preContext")

	local logger = Addon:ForLogContext({additional = "context", some = 1, more = true, context = { 1, 3, 5 }})
	logger:LogInfo("Using ForLogContext")
	logger:LogInfo("Using ForLogContext and specifying more arguments: {player}", "Arthas")
	logger:LogInfo("Using ForLogContext and overriding properties: {some}", "overriden")
	logger:PushLogProperty("pushedLater", "woo")
	logger:LogInfo("Using ForLogContext, with additional properties pushed separately")

	Addon:PushLogProperty("pushed1", 1)
	logger = Addon:ForLogContext()
	logger:PushLogProperty("pushed2", 2)
	Addon:PopLogProperty("pushed1")
	logger:LogInfo("Using ForContext, with an additional base property and a self-owned property")

	Addon:PushLogProperty("pushed1", 1)
	logger = Addon:ForLogContext()
	logger:PopLogProperty("pushed1")
	logger:LogInfo("Using ForContext, with a popped property")
	Addon:LogInfo("After popping an extra property within ForContext")

	Addon:PushLogProperty("additional", "values")
	Addon:PushLogProperty("are", { "c", "o", "o", "l" })
	Addon:LogInfo("Using PushLogProperty")
	Addon:PopLogProperty("additional", "are")

	Addon:AddLogEnum("TestEnum", {
		KEY1 = 1,
		KEY2 = 2,
		KEY3 = 3
	})
	Addon:LogInfo("Using enum values: {enumValue#TestEnum}", 2)

	self.embeds[Addon] = nil
	self.levels[Addon.name or ""] = nil
end

for target in pairs(LibLog.embeds) do
	LibLog:Embed(target)
end

LibLog:RegisterSink("BuiltIn", ChatFrameSink)
