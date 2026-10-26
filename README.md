# LibLog

LibLog is a structured logging library for World of Warcraft addons.

```lua
MyAddon:LogInfo("My current health is {health}, and I have {mana} mana", UnitHealth("player"), UnitPower("player"))
-- MyAddon: My current health is 50, and I have 100 mana
```

Out of the box, LibLog prints readable messages to the chat window, and that's all most users will ever see. Behind the scenes, each log also records its
values as named properties, which other addons (called _sinks_) can capture and inspect:

* [LogSink: Table](https://github.com/Snakybo/LogSink-Table) shows logs in an in-game window.
* [LogSink: SavedVariables](https://github.com/Snakybo/LogSink-SavedVariables) writes logs to your saved variables.

See [API.md](API.md) for the full API reference.

## Features

* Simple logging API with well-known levels: trace, debug, info, warning, error, and fatal.
* Configurable minimum log level per addon.
* Structured logging using [Message Templates](https://messagetemplates.org/).
* Custom sinks to capture and process logs in real-time.
* Works out of the box with AceAddon-3.0 addons and modules.

## Why structured logging?

Traditional logging writes plain text:

```lua
print(UnitName("player") .. ": UNIT_SPELLCAST_SUCCEEDED " .. spellName)
```

```txt
Thrall: UNIT_SPELLCAST_SUCCEEDED Bloodlust
Khadgar: UNIT_SPELLCAST_SUCCEEDED Blink
Thrall: UNIT_SPELLCAST_FAILED Lightning Bolt
Khadgar: UNIT_SPELLCAST_SUCCEEDED Fire Blast
```

This is easy to read, but hard to analyze. Who cast Bloodlust? Whose casts failed? Who cast the most spells? Answering that means parsing text, which only
gets harder in a 20-player raid.

Structured logging keeps the values separate from the text. LibLog uses [Message Templates](https://messagetemplates.org/), where each `{placeholder}`
in the message becomes a named property:

```lua
MyAddon:LogInfo("{name}: {eventName} {spellName}", UnitName("player"), event, spellName)
```

```lua
{
  message = "Thrall: UNIT_SPELLCAST_SUCCEEDED Bloodlust",
  properties = {
    name = "Thrall",
    eventName = "UNIT_SPELLCAST_SUCCEEDED",
    spellName = "Bloodlust"
  }
  -- <other fields omitted>
}
```

A sink can now filter, group, or count logs by any of these properties.

## Getting started

### Embedding

LibLog must be embedded into your addon. With AceAddon-3.0, add it to the list of libraries:

```lua
MyAddon = LibStub("AceAddon-3.0"):NewAddon("MyAddon", "LibLog")
```

Without AceAddon-3.0, embed it manually using LibStub. Make sure your addon has a `name` field, LibLog uses it to identify your addon:

```lua
MyAddon = { name = "MyAddon" }
LibStub("LibLog"):Embed(MyAddon)
```

Then start logging:

```lua
MyAddon:LogInfo("Hello {name}!", MyAddon.name)
-- MyAddon: Hello MyAddon!
```

### Log levels

| Level     | Method       | When to use                                                                               |
| --------- | ------------ | ----------------------------------------------------------------------------------------- |
| `FATAL`   | `LogFatal`   | A critical or otherwise unrecoverable error that must halt execution.                     |
| `ERROR`   | `LogError`   | A high-severity logic issue that leaves functionality unavailable or expectations broken. |
| `WARNING` | `LogWarning` | User error, or other non-breaking issues.                                                 |
| `INFO`    | `LogInfo`    | General status updates and runtime milestones.                                            |
| `DEBUG`   | `LogDebug`   | Code paths and state changes that help determine how something happened.                  |
| `TRACE`   | `LogTrace`   | High-frequency, noisy data that is rarely enabled outside of debugging.                   |

Logs below your addon's minimum log level are ignored. The default minimum is `INFO`.

### Formatting

Placeholders support `string.format` specifiers, without the leading `%`:

```lua
MyAddon:LogInfo("Current progress {progress:.2f}", 0.124567890)
-- MyAddon: Current progress 0.12
```

Values are matched to placeholders by position, not by name. Placeholder names may only contain letters and digits.

### Configuring the log level

Change the minimum log level of your addon with:

```lua
local LibLog = LibStub("LibLog")

MyAddon:SetLogLevel(LibLog.LogLevel.DEBUG)
MyAddon:GetLogLevel()
```

LibLog doesn't save the log level between sessions, that's up to your addon. The easiest way is to pass your saved variables to
`SetLogLevelFromConfigTable` on startup:

```lua
function MyAddon:OnInitialize()
  self.db = LibStub("AceDB-3.0"):New("MyAddonDB")
  self:SetLogLevelFromConfigTable(self.db.global)
end
```

With AceConfig-3.0, you can add a dropdown that changes and saves the log level:

```lua
logLevel = MyAddon:GetLogLevelOptionObject(MyAddon.db.global)

-- Or, to customize the option
logLevel = Mixin(MyAddon:GetLogLevelOptionObject(MyAddon.db.global), {
  order = 10
})
```

Building your own dropdown? Use `LibLog.LogLevel`, `LibLog.configKey`, `SetLogLevel`, and `GetLogLevel`.

## Advanced usage

### Expensive logs

If a log needs expensive work to gather its values, that work is wasted when the log is filtered out. Pass a function instead, and it will only run when the
log is actually processed:

```lua
MyAddon:LogTrace("Currently in a raid with {members}", function()
  local members = {}

  for i = 1, GetNumGroupMembers() do
    table.insert(members, UnitName("raid" .. i))
  end

  return members
end)
```

Alternatively, check the level yourself with `IsLogLevelEnabled`:

```lua
if MyAddon:IsLogLevelEnabled(LibLog.LogLevel.DEBUG) then
  MyAddon:LogDebug("Currently in a raid with {members}", GetRaidMembers())
end
```

### Fatal logs

`LogFatal` logs like any other level, but also raises a Lua error, which halts execution just like `error(...)` and shows up in BugSack or the default error
frame.

All log functions return `nil`, so you can log and exit in one statement. This is especially useful for `LogFatal`, since language servers such as LuaLS
don't know it never returns:

```lua
if data == nil then
  return MyAddon:LogFatal("Unable to load {key}", key)
end
```

### Additional properties

You can add properties to every log from your addon, without including them in the message. If the value is a function, it's called for every log, so the
value is always up-to-date.

```lua
MyAddon:PushLogProperty("zone", GetZoneText())
MyAddon:PushLogProperty("health", function()
  return UnitHealth("player")
end)

MyAddon:LogInfo("This log includes zone and health")

MyAddon:PopLogProperty("zone", "health")
```

To avoid having to pop properties manually, use `WithLogContext`, or create a separate logger with `ForLogContext`:

```lua
MyAddon:WithLogContext({ encounterId = encounterId }, function(logger)
  logger:LogInfo("This log includes encounterId")
end)

local logger = MyAddon:ForLogContext({ encounterId = encounterId })
logger:LogInfo("This log also includes encounterId")
```

### Enums

Enum values are often just numbers, which aren't very useful in a log:

```lua
local Scope = {
  PROFILE = 1,
  GLOBAL = 2
}
```

Register the enum with `AddLogEnum`, then add `#EnumName` to the placeholder to log the key instead of the value:

```lua
MyAddon:AddLogEnum("Scope", Scope)
MyAddon:LogInfo("Current scope is {scope#Scope}", Scope.PROFILE)
-- MyAddon: Current scope is PROFILE
```

If the enum isn't registered, or the value isn't part of it, the raw value is logged.

### Modules

LibLog can be embedded into AceAddon-3.0 modules as well. Modules share the log level of their addon, and their name is captured in the `module` field
of each log:

```lua
MyAddon:NewModule("MyModule", "LibLog")
```

Without AceAddon-3.0, set a `moduleName` field before embedding:

```lua
MyModule = {
  name = "MyAddon",
  moduleName = "MyModule"
}

LibStub("LibLog"):Embed(MyModule)
```

## Custom sinks

Sinks receive every log, from every addon that uses LibLog. Register one with a function:

```lua
local LibLog = LibStub("LibLog")

--- @param message LibLog.LogMessage
LibLog:RegisterSink("MyLogSink", function(message)
  print(message.message)
end)
```

Or with a table that has an `OnLogMessageReceived` method:

```lua
--- @class MySink : LibLog.Sink
local MySink = {}

--- @param message LibLog.LogMessage
function MySink:OnLogMessageReceived(message)
  print(message.message)
end

LibLog:RegisterSink("MyLogSink", MySink)
```

Each message contains everything about the log, including the value of each property:

```lua
{
  message = "My character name is Arthas on realm Frostmourne",
  template = "My character name is {charName} on realm {realmName}",
  addon = "MyAddon",
  level = 300, -- LibLog.LogLevel.INFO
  time = 1771420921,
  sequenceId = 1,
  properties = {
    charName = "Arthas",
    realmName = "Frostmourne"
  }
}
```

Sinks can be enabled and disabled at any time. The built-in sink that prints to the chat window is called `BuiltIn`:

```lua
LibLog:DisableSink("BuiltIn")
LibLog:EnableSink("BuiltIn")
```
