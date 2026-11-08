--!nonstrict
-- Shows the first queued prompt, in the style of the shell's polkit panel. The answer is written
-- straight to the client's private directory (shared.reply) and never goes through the state
-- channel; the service only learns the id is done. Escape or Cancel cancels the current prompt.

local shared = require("./shared.luau")

local current = nil -- the request on screen
local secret = ""
local repeated = ""
local mismatch = false
local isOpen = false

local function wipeInputs()
  secret = ""
  repeated = ""
  mismatch = false
end

local function settle(result, value)
  if current == nil then
    return
  end
  local id = current.id
  shared.reply(id, result, value)
  current = nil
  wipeInputs()
  noctalia.state.set("done", id)
end

local function title(request)
  if request.title ~= "" then
    return request.title
  end
  return noctalia.tr(if request.origin == "ssh" then "ssh-title" else "gpg-title")
end

local function okLabel(request)
  if request.ok ~= "" then
    return request.ok
  end
  return noctalia.tr(if request.kind == "pin" then "unlock" else "ok")
end

local function placeholder(request)
  if request.prompt ~= "" then
    return (string.gsub(request.prompt, "%s*:%s*$", ""))
  end
  if request.visible then
    return noctalia.tr("answer-placeholder")
  end
  return noctalia.tr("passphrase-placeholder")
end

function onSecretChange(value)
  secret = if type(value) == "string" then value else ""
  if mismatch then
    mismatch = false
    render()
  end
end

function onRepeatChange(value)
  repeated = if type(value) == "string" then value else ""
  if mismatch then
    mismatch = false
    render()
  end
end

function onSubmit()
  if current == nil then
    return
  end
  if current.kind == "pin" then
    if current.repeat_ and secret ~= repeated then
      mismatch = true
      render()
      return
    end
    settle("ok", secret)
  else
    settle("ok")
  end
end

function onNotOk()
  settle("notok")
end

function onCancel()
  settle("cancel")
end

local function buttons(request)
  if request.no_buttons then
    return nil
  end
  local row = {}
  local single = request.kind == "message" or request.one_button
  if not single then
    table.insert(row, ui.button({
      text = if request.cancel ~= "" then request.cancel else noctalia.tr("cancel"),
      variant = "outline",
      onClick = "onCancel",
    }))
    if request.kind == "confirm" and request.notok ~= "" then
      table.insert(row, ui.button({ text = request.notok, variant = "outline", onClick = "onNotOk" }))
    end
  end
  table.insert(row, ui.button({ text = okLabel(request), variant = "primary", onClick = "onSubmit" }))
  return ui.row({ gap = 8, justify = "end", align = "center" }, row)
end

function render()
  if not isOpen then
    return
  end
  local request = current
  if request == nil then
    panel.render(ui.column({}, {}))
    return
  end

  local body = {
    ui.row({ gap = 14, align = "center" }, {
      ui.glyph({
        name = if request.origin == "ssh" then "terminal-2" else "key",
        size = 32,
        color = "on_surface_variant",
      }),
      ui.label({ text = title(request), fontSize = 18, fontWeight = "bold", color = "primary", flexGrow = 1 }),
    }),
  }
  if request.description ~= "" then
    table.insert(body, ui.label({ text = request.description, color = "on_surface", maxLines = 10 }))
  end
  if request.error ~= "" then
    table.insert(body, ui.label({ text = request.error, color = "error", maxLines = 3 }))
  end

  if request.kind == "pin" then
    table.insert(body, ui.input({
      key = "secret-" .. request.id,
      value = "",
      placeholder = placeholder(request),
      password = not request.visible,
      focus = true,
      onChange = "onSecretChange",
      onSubmit = if request.repeat_ then nil else "onSubmit",
    }))
    if request.repeat_ then
      table.insert(body, ui.input({
        key = "repeat-" .. request.id,
        value = "",
        placeholder = if request.repeat_prompt ~= ""
          then (string.gsub(request.repeat_prompt, "%s*:%s*$", ""))
          else noctalia.tr("repeat-placeholder"),
        password = true,
        onChange = "onRepeatChange",
        onSubmit = "onSubmit",
      }))
      if mismatch then
        table.insert(body, ui.label({
          text = if request.repeat_error ~= "" then request.repeat_error else noctalia.tr("mismatch"),
          color = "error",
        }))
      end
    end
  end

  local row = buttons(request)
  if row ~= nil then
    table.insert(body, row)
  end
  panel.render(ui.column({ gap = 12, padding = 20, align = "stretch" }, body))
end

-- Lua keywords: the request field "repeat" is read as repeat_.
local function normalize(request)
  local copy = table.clone(request)
  copy.repeat_ = request["repeat"] == true
  return copy
end

local function sync(queue)
  local head = if type(queue) == "table" then queue[1] else nil
  if head == nil then
    current = nil
    wipeInputs()
    if isOpen then
      panel.close()
    end
    return
  end
  if current == nil or current.id ~= head.id then
    current = normalize(head)
    wipeInputs()
  end
  render()
end

noctalia.state.watch("queue", sync)

function onOpen(_context)
  isOpen = true
  noctalia.state.set("panel_open", true)
  current = nil
  sync(noctalia.state.get("queue"))
end

function onClose()
  isOpen = false
  -- Escape (or anything else that closes the panel) cancels the prompt on screen.
  settle("cancel")
  noctalia.state.set("panel_open", false)
end
