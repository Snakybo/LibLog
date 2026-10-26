# LibLog API

```lua
local LibLog = LibStub("LibLog")
```

* All functions are called with `:` syntax.
* `Logger` refers to any object LibLog has been [embedded](#embed) into, or a logger created with [`ForLogContext`](#forlogcontext).
* Values passed to a log function are deep-copied when the log is processed, so they are safe to modify afterwards.
* Requires [LibStub](https://www.curseforge.com/wow/addons/libstub) to be loaded first.

## Contents

* [Types](#types)
* [Constants](#constants)
* [Message templates](#message-templates)
* [Embedding](#embedding)
* [Logging](#logging)
* [Log levels](#log-levels)
* [Properties](#properties)
* [Enums](#enums)
* [Sinks](#sinks)
* [Utilities](#utilities)

## Types

### LibLog.LogLevel

| Value     | Numeric value | Description                                                                                |
| --------- | :-----------: | ------------------------------------------------------------------------------------------ |
| `NONE`    | `0`           | The lowest level, shown as an option in the [log level dropdown](#getlogleveloptionobject). |
| `TRACE`   | `100`         | High-frequency, noisy data that is rarely enabled outside of debugging.                    |
| `DEBUG`   | `200`         | Code paths and state changes that are useful when determining how something happened.      |
| `INFO`    | `300`         | General status updates and runtime milestones.                                             |
| `WARNING` | `400`         | User-error, or other non-breaking issues.                                                  |
| `ERROR`   | `500`         | A high-severity logic issue that leaves functionality unavailable or expectations broken.  |
| `FATAL`   | `600`         | A critical or otherwise unrecoverable error that must halt execution.                      |

Functions that take a `LibLog.LogLevel` also accept the name of the level (case-insensitive, e.g. `"debug"`) in its place, unless noted otherwise.

### LibLog.LogMessage

The object passed to [sinks](#sinks) for every processed log.

| Field        | Type                     | Description                                                                                                      |
| ------------ | ------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `message`    | `string`                 | The human-readable log string, with all placeholders replaced.                                                   |
| `template`   | `string`                 | The unprocessed [message template](#message-templates).                                                          |
| `level`      | `LibLog.LogLevel`        | The level of the log. Can be compared against [`LibLog.LogLevel`](#liblogloglevel), or stringified using [`LibLog.labels`](#libloglabels). |
| `addon`      | `string?`                | The name of the source addon, `nil` if the logger has no `name`.                                                 |
| `module`     | `string?`                | The name of the source module, `nil` if the logger is not a [module](#modules).                                  |
| `time`       | `integer`                | The number of seconds that have elapsed since the Unix epoch.                                                    |
| `sequenceId` | `integer`                | The unique sequence identifier of the log within the current second, starting at `1`.                            |
| `properties` | `table<string, unknown>` | All properties that have been extracted from the template, or [pushed](#properties) onto the logger.             |

* `time` and `sequenceId` combined uniquely identify a log message, and can be used to sort logs in the order they were produced. The sequence is shared between all addons.
* If a template property and a pushed property have the same name, the template property takes precedence.
* If a template property uses an [enum](#enums), its value in `properties` is the enum key instead of the raw value.

### LibLog.Sink

| Field                  | Type                                                                | Description                                      |
| ---------------------- | ------------------------------------------------------------------- | ------------------------------------------------ |
| `OnLogMessageReceived` | `fun(self: LibLog.Sink, message: LibLog.LogMessage)`                | Called for every log processed by LibLog.        |

### LibLog.MessageTemplate

The parsed form of a [message template](#message-templates), see [`GetFormat`](#getformat).

| Field          | Type                               | Description                                                                                           |
| -------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `format`       | `string`                           | The template with each placeholder replaced by its `%` format specifier, e.g. `%d`, `%.2f`, or `%s`.  |
| `stringFormat` | `string`                           | The template with each placeholder replaced by `%s`.                                                  |
| `properties`   | `LibLog.MessageTemplateProperty[]` | The placeholders in the template, in order of appearance.                                             |

### LibLog.MessageTemplateProperty

| Field      | Type      | Description                                                                                      |
| ---------- | --------- | ------------------------------------------------------------------------------------------------ |
| `name`     | `string`  | The name of the property, which is used as key in [`LibLog.LogMessage`](#libloglogmessage)`.properties`. |
| `format`   | `string`  | The `%` format specifier of the property, e.g. `%d`, `%.2f`, or `%s` if none was specified.      |
| `replacer` | `string?` | The name of the [enum](#enums) used to format the property, if any.                              |

## Constants

### LibLog.labels

A table that maps each [`LibLog.LogLevel`](#liblogloglevel) (except `NONE`) to a short, three letter label: `TRC`, `DBG`, `INF`, `WRN`, `ERR`, and `FTL`.

#### Example

```lua
local LibLog = LibStub("LibLog")
print(LibLog.labels[LibLog.LogLevel.WARNING]) -- WRN
```

### LibLog.configKey

The key used to store the log level in a configuration table, by [`SetLogLevelFromConfigTable`](#setloglevelfromconfigtable) and [`GetLogLevelOptionObject`](#getlogleveloptionobject). Its value is `"logLevel"`.

#### Example

```lua
local LibLog = LibStub("LibLog")
MyAddon.db.global[LibLog.configKey] = LibLog.LogLevel.DEBUG
```

## Message templates

LibLog uses [Message Templates](https://messagetemplates.org/). Placeholders in the template are enclosed in braces, and are replaced by the values passed to the log function.

| Syntax               | Example                | Description                                                                                  |
| -------------------- | ---------------------- | -------------------------------------------------------------------------------------------- |
| `{name}`             | `{health}`             | Captures the value as property `name`.                                                       |
| `{name:format}`      | `{progress:.2f}`       | Formats the value using a `string.format` specifier, without the leading `%`.                |
| `{name#Enum}`        | `{scope#Scope}`        | Formats the value using a registered [enum](#enums).                                         |
| `{name#Enum:format}` | `{scope#Scope:s}`      | Combines both of the above.                                                                  |

* Values are matched to placeholders by position, not by name. Excess values are ignored, and missing values are `nil`.
* Property and enum names may only contain letters and digits.
* Tables are serialized into the message, e.g. `{ a = 1, b = "two", }`. Circular references are replaced by `<circular reference>`.
* Frames and other UI objects are captured as their `tostring` value.
* A literal `%` in the template does not need to be escaped.

### Callback values

Instead of values, a single function can be passed. The function is only called if the log is processed, and its return values are used as the values for the template. This prevents expensive computations for logs that would be filtered out by the [log level](#log-levels).

If the function raises an error, the error is passed to the error handler and the log is processed without values.

#### Example

```lua
MyAddon:LogTrace("Currently in a raid with {members}", function()
	local result = {}

	for i = 1, GetNumGroupMembers() do
		table.insert(result, UnitName("raid" .. i))
	end

	return result
end)
```

## Embedding

### Embed

```lua
LibLog:Embed(target: T): T
```

Embed LibLog into the target object, making all `Logger` functions available on it. Returns the target.

When using AceAddon-3.0, LibLog can be embedded by adding `"LibLog"` to the list of libraries when creating the addon or module, which calls this function automatically.

The target should have a `name` field, which is used as the name of the addon. Without a `name`, the logger uses the global default log level, which cannot be changed, and logs have no `addon`.

| Field        | Type      | Description                                                    |
| ------------ | --------- | -------------------------------------------------------------- |
| `name`       | `string?` | The name of the addon. Set automatically by AceAddon-3.0.      |
| `moduleName` | `string?` | The name of the module. Set automatically by AceAddon-3.0.     |

#### Example

```lua
-- Using AceAddon-3.0
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibLog")

-- Using LibStub
MyAddon = LibStub("LibLog"):Embed({
	name = "MyAddon"
})
```

### Modules

A logger with a `moduleName` is treated as a module. If the `name` of a module ends with `_<moduleName>`, as is the case for AceAddon-3.0 modules, the suffix is removed to determine the addon name.

Modules share the [log level](#log-levels) and [enums](#enums) of their addon, and the module name is captured in the `module` field of the [`LibLog.LogMessage`](#libloglogmessage).

#### Example

```lua
-- Using AceAddon-3.0
MyModule = MyAddon:NewModule("MyModule", "LibLog")

-- Using LibStub
MyModule = LibStub("LibLog"):Embed({
	name = "MyAddon_MyModule",
	moduleName = "MyModule"
})
```

## Logging

All log functions accept a [message template](#message-templates), followed by the values for its placeholders, or a [callback](#callback-values) that returns them.

Log functions return an `unknown` value, which is always `nil`. This allows using `return MyAddon:LogError(...)` to log and exit the running function in one statement.

### LogTrace

```lua
Logger:LogTrace(template: string, ...: any): unknown
Logger:LogTrace(template: string, callback: fun(): ...any): unknown
```

Log a `TRACE` message. Trace logs should be used for high-frequency logs or low-level data, for example raw calculations.

#### Example

```lua
MyAddon:LogTrace("Received {event} with {args}", event, { ... })
```

### LogDebug

```lua
Logger:LogDebug(template: string, ...: any): unknown
Logger:LogDebug(template: string, callback: fun(): ...any): unknown
```

Log a `DEBUG` message. Debug logs should be used to verify code paths, state changes, or event registration during active development and testing.

#### Example

```lua
MyAddon:LogDebug("Registered event {event}", "PLAYER_ENTERING_WORLD")
```

### LogInfo

```lua
Logger:LogInfo(template: string, ...: any): unknown
Logger:LogInfo(template: string, callback: fun(): ...any): unknown
```

Log an `INFO` message. Info logs should be used for general status updates and milestones, for example successful loading, profile changes, or user-triggered actions.

#### Example

```lua
MyAddon:LogInfo("My current health is {health}, and I have {mana} mana", UnitHealth("player"), UnitPower("player"))
```

### LogWarning

```lua
Logger:LogWarning(template: string, ...: any): unknown
Logger:LogWarning(template: string, callback: fun(): ...any): unknown
```

Log a `WARNING` message. Warning logs should be the result of user error or other non-breaking issues, for example optional settings that are missing, or invalid input.

#### Example

```lua
MyAddon:LogWarning("Unknown command {command}", input)
```

### LogError

```lua
Logger:LogError(template: string, ...: any): unknown
Logger:LogError(template: string, callback: fun(): ...any): unknown
```

Log an `ERROR` message. Error logs should indicate a high severity logic failure that likely indicates a bug, though execution can continue, for example an API that returns unexpected data.

#### Example

```lua
local info = C_Spell.GetSpellInfo(spellId)

if info == nil then
	return MyAddon:LogError("Unable to find spell {spellId}", spellId)
end
```

### LogFatal

```lua
Logger:LogFatal(template: string, ...: any): unknown
Logger:LogFatal(template: string, callback: fun(): ...any): unknown
```

Log a `FATAL` message, and raise an error with the formatted message. Fatal logs should be used sparingly, when execution cannot continue because doing so may lead to data corruption or unrecoverable states, for example missing libraries or broken saved variables.

The error is always raised, even if the `FATAL` level is filtered out by the [log level](#log-levels). In that case, the log is not sent to the [sinks](#sinks).

#### Example

```lua
if MyAddonDB.version > CURRENT_VERSION then
	return MyAddon:LogFatal("Saved variables version {version} is not supported", MyAddonDB.version)
end
```

### LogVerbose

```lua
Logger:LogVerbose(template: string, ...: any): unknown
Logger:LogVerbose(template: string, callback: fun(): ...any): unknown
```

> [!WARNING]
> Deprecated, use [`LogTrace`](#logtrace) instead.

Log a `TRACE` message.

## Log levels

Each addon has a minimum log level. Logs with a lower level are ignored, and are not sent to the [sinks](#sinks). The default minimum log level is `INFO`.

The log level is not persisted by LibLog. Use [`SetLogLevelFromConfigTable`](#setloglevelfromconfigtable) to restore it from your saved variables on startup.

### IsLogLevelEnabled

```lua
Logger:IsLogLevelEnabled(level: LibLog.LogLevel): boolean
Logger:IsLogLevelEnabled(levelName: string): boolean
```

Check whether logs of the given level are currently processed for this addon. Always returns `true` for `FATAL`.

`levelName` must be a valid level name.

#### Example

```lua
local LibLog = LibStub("LibLog")

if MyAddon:IsLogLevelEnabled(LibLog.LogLevel.DEBUG) then
	MyAddon:LogDebug("Currently in a raid with {members}", GetRaidMembers())
end
```

### GetLogLevel

```lua
Logger:GetLogLevel(): LibLog.LogLevel
```

Get the minimum log level of this addon. Returns the default log level if no level has been set, or if the logger has no `name`.

#### Example

```lua
local level = MyAddon:GetLogLevel()
```

### SetLogLevel

```lua
Logger:SetLogLevel(level?: LibLog.LogLevel)
Logger:SetLogLevel(levelName: string)
```

Set the minimum log level of this addon. Passing `nil`, or an invalid level name, resets it to the default log level.

Does nothing if the logger has no `name`.

#### Example

```lua
local LibLog = LibStub("LibLog")
MyAddon:SetLogLevel(LibLog.LogLevel.DEBUG)
MyAddon:SetLogLevel("debug")
```

### SetLogLevelFromConfigTable

```lua
Logger:SetLogLevelFromConfigTable(configTable: table)
```

Set the minimum log level of this addon from a configuration table, usually your saved variables. The level is read from the [`LibLog.configKey`](#liblogconfigkey) field, and is left unchanged if the field is not set.

Does nothing if the logger has no `name`.

#### Example

```lua
function MyAddon:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("MyAddonDB")
	self:SetLogLevelFromConfigTable(self.db.global)
end
```

### GetLogLevelOptionObject

```lua
Logger:GetLogLevelOptionObject(configTable: table): table
```

Create an AceConfig-3.0 `select` option, which shows a dropdown to change the minimum log level of this addon.

The selected level is applied immediately, and stored in the [`LibLog.configKey`](#liblogconfigkey) field of `configTable`, so it can be restored using [`SetLogLevelFromConfigTable`](#setloglevelfromconfigtable).

#### Example

```lua
local options = {
	type = "group",
	args = {
		logLevel = Mixin(MyAddon:GetLogLevelOptionObject(MyAddon.db.global), {
			order = 10
		})
	}
}
```

## Properties

Properties are added to the `properties` table of every [`LibLog.LogMessage`](#libloglogmessage) produced by a logger, without appearing in the message itself.

A property value can be a function, which is called every time a log is processed, and its return value is used as the property value. If the function raises an error, the error is passed to the error handler and the property is omitted.

### PushLogProperty

```lua
Logger:PushLogProperty(name: string, value: any)
Logger:PushLogProperty(name: string, callback: fun(): any)
```

Add a property to all further logs from this logger, until it is [popped](#poplogproperty). Pushing a property with an existing name replaces it.

#### Example

```lua
MyAddon:PushLogProperty("zone", GetZoneText())
MyAddon:PushLogProperty("health", function()
	return UnitHealth("player")
end)
```

### PopLogProperty

```lua
Logger:PopLogProperty(...: string)
```

Remove one or more previously pushed properties from this logger.

#### Example

```lua
MyAddon:PopLogProperty("zone", "health")
```

### ForLogContext

```lua
Logger:ForLogContext(properties?: table<string, any>): Logger
```

Create a new logger that adds the given properties to all logs it produces. The new logger has access to all functions and fields of the original.

* The new logger starts with a copy of the properties of the original logger. Properties pushed to, or popped from, either logger afterwards do not affect the other.
* If `properties` contains a property that already exists on the original logger, the value in `properties` is used.

#### Example

```lua
local logger = MyAddon:ForLogContext({
	encounterId = encounterId,
	difficulty = difficultyId
})

logger:LogInfo("Encounter started")
```

### WithLogContext

```lua
Logger:WithLogContext(properties: table<string, any>, closure: fun(logger: Logger))
```

Call `closure` with a new logger created by [`ForLogContext`](#forlogcontext). This avoids having to push and pop properties manually.

Errors raised by `closure` are re-raised.

#### Example

```lua
MyAddon:WithLogContext({ encounterId = encounterId }, function(logger)
	logger:LogInfo("Encounter started")
	logger:LogDebug("Boss health is {health}", UnitHealth("boss1"))
end)
```

## Enums

### AddLogEnum

```lua
Logger:AddLogEnum(id: string, enum: table<string, any>)
```

Register an enum-like table with the given name, which can be used to format values in [message templates](#message-templates) using `{name#id}`.

* Values are formatted as their key in the enum. Values that are not in the enum are formatted as-is.
* Enums are registered per addon, and are shared with the addon's [modules](#modules). Registering an enum with an existing name replaces it.

#### Example

```lua
local Scope = {
	PROFILE = 1,
	GLOBAL = 2
}

MyAddon:AddLogEnum("Scope", Scope)
MyAddon:LogInfo("Current scope is {scope#Scope}", Scope.PROFILE)
-- Current scope is PROFILE
```

## Sinks

Sinks receive every processed [`LibLog.LogMessage`](#libloglogmessage), from all addons. LibLog registers a built-in sink called `"BuiltIn"`, which prints logs to the default chat frame.

Errors raised by a sink are passed to the error handler, and do not prevent other sinks from receiving the log.

### RegisterSink

```lua
LibLog:RegisterSink(name: string, callback: fun(message: LibLog.LogMessage))
LibLog:RegisterSink(name: string, sink: LibLog.Sink)
```

Register a sink with the given name. The sink is enabled immediately. Registering a sink with an existing name replaces it.

When a [`LibLog.Sink`](#liblogsink) is given, its `OnLogMessageReceived` function is called with `:` syntax. Raises an error if `callback` is neither a function nor a table with an `OnLogMessageReceived` function.

#### Example

```lua
local LibLog = LibStub("LibLog")

-- Using a function
LibLog:RegisterSink("MyLogSink", function(message)
	print(message.message)
end)

-- Using a table
local MySink = {}

function MySink:OnLogMessageReceived(message)
	print(LibLog.labels[message.level], message.message)
end

LibLog:RegisterSink("MyLogSink", MySink)
```

### EnableSink

```lua
LibLog:EnableSink(name: string)
```

Enable a previously disabled sink. Does nothing if no sink with the given name is registered.

#### Example

```lua
local LibLog = LibStub("LibLog")
LibLog:EnableSink("MyLogSink")
```

### DisableSink

```lua
LibLog:DisableSink(name: string)
```

Disable a sink, preventing it from receiving logs until it is [re-enabled](#enablesink). Does nothing if no sink with the given name is registered.

#### Example

```lua
local LibLog = LibStub("LibLog")

-- Stop printing logs to the chat frame
LibLog:DisableSink("BuiltIn")
```

### GetSinks

```lua
LibLog:GetSinks(enabledOnly?: boolean): string[]
```

Get the names of all registered sinks, or only the enabled sinks if `enabledOnly` is `true`. The names are not sorted.

#### Example

```lua
local LibLog = LibStub("LibLog")

for _, name in ipairs(LibLog:GetSinks(true)) do
	print(name)
end
```

## Utilities

These functions are mostly useful when implementing a [sink](#sinks).

### GetFormat

```lua
LibLog:GetFormat(template: string): LibLog.MessageTemplate
```

Parse a [message template](#message-templates). The result is cached, and shared between all callers, so it should not be modified.

#### Example

```lua
local LibLog = LibStub("LibLog")
local template = LibLog:GetFormat("Current progress {progress:.2f}")

print(template.format) -- Current progress %.2f
print(template.stringFormat) -- Current progress %s
print(template.properties[1].name) -- progress
```

### GetNextSequenceId

```lua
LibLog:GetNextSequenceId(): integer, integer
```

Get the current time, and the next sequence ID within the current second. This advances the internal sequence counter, which is shared with the `sequenceId` of each [`LibLog.LogMessage`](#libloglogmessage).

#### Example

```lua
local LibLog = LibStub("LibLog")
local time, sequenceId = LibLog:GetNextSequenceId()
```
