--!nonstrict
-- Queue of pending prompts. Requests arrive from noctalia-pinentry / noctalia-askpass:
--   noctalia msg plugin lbssousa/secret-prompts:service all request <json>
--   noctalia msg plugin lbssousa/secret-prompts:service all cancel <id>
--   noctalia msg plugin lbssousa/secret-prompts:service all ping
-- Only display text goes through here; the panel writes the answer straight to the client.

local shared = require("./shared.luau")

local KINDS = { pin = true, confirm = true, message = true }
local STRING_FIELDS = {
  "title", "description", "prompt", "error", "ok", "cancel", "notok", "repeat_prompt", "repeat_error",
}
local BOOL_FIELDS = { "repeat", "one_button", "visible", "no_buttons" }
local MAX_QUEUE = 16

local queue = {}
-- togglePanel closes an open panel, so a second request arriving before the panel reports
-- panel_open must not toggle again.
local openRequestedAt = nil
local OPEN_GRACE_MS = 2000

local function publish()
  noctalia.state.set("queue", queue)
end

local function indexOf(id)
  for i, request in ipairs(queue) do
    if request.id == id then
      return i
    end
  end
  return nil
end

local function remove(id)
  local i = indexOf(id)
  if i ~= nil then
    table.remove(queue, i)
    publish()
  end
end

local function showPanel()
  if #queue == 0 or noctalia.state.get("panel_open") == true then
    return
  end
  local now = noctalia.nowMs()
  if openRequestedAt ~= nil and now - openRequestedAt < OPEN_GRACE_MS then
    return
  end
  openRequestedAt = now
  noctalia.togglePanel(shared.PANEL)
end

-- Keeps only known fields with the right types, so the panel can trust the shape.
local function sanitize(raw)
  if type(raw) ~= "table" or not shared.validId(raw.id) or not KINDS[raw.kind] then
    return nil
  end
  local request = {
    id = raw.id,
    kind = raw.kind,
    origin = if raw.origin == "ssh" then "ssh" else "gpg",
  }
  for _, key in ipairs(STRING_FIELDS) do
    request[key] = if type(raw[key]) == "string" then raw[key] else ""
  end
  for _, key in ipairs(BOOL_FIELDS) do
    request[key] = raw[key] == true
  end
  -- A gpg secret is always masked, whatever the request says.
  if request.origin == "gpg" then
    request.visible = false
    request.no_buttons = false
  end
  return request
end

function onIpc(event, payload)
  if event == "ping" then
    return
  end
  if event == "cancel" then
    remove(noctalia.string.trim(payload or ""))
    return
  end
  if event ~= "request" then
    return
  end
  local raw = noctalia.json.decode(payload or "")
  local request = sanitize(raw)
  if request == nil or indexOf(request.id) ~= nil then
    return
  end
  if #queue >= MAX_QUEUE then
    shared.reply(request.id, "cancel")
    return
  end
  local dir = shared.promptDir(request.id)
  if dir == nil or not noctalia.writeFile(dir .. "/ack", "1") then
    return
  end
  table.insert(queue, request)
  publish()
  showPanel()
end

-- The panel settled a request (answered or cancelled) and already wrote the reply.
noctalia.state.watch("done", function(id)
  if type(id) == "string" then
    remove(id)
  end
end)

-- Closed with prompts still waiting (Escape cancels only the current one): bring it back.
noctalia.state.watch("panel_open", function(open)
  -- The panel answered the toggle either way: the next request may open it again.
  openRequestedAt = nil
  if open ~= true then
    showPanel()
  end
end)

publish()
