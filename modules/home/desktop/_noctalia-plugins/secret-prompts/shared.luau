--!nonstrict
-- Paths and validation shared by the service and the panel.

local M = {}

M.PANEL = "lbssousa/secret-prompts:prompt"

-- 16 random bytes in hex, made by the client; anything else is refused, so a request can never
-- point the plugin at another path.
function M.validId(id)
  return type(id) == "string" and #id == 32 and string.match(id, "^[0-9a-f]+$") ~= nil
end

function M.promptDir(id)
  local runtime = noctalia.getenv("XDG_RUNTIME_DIR")
  if runtime == nil or runtime == "" or not M.validId(id) then
    return nil
  end
  return runtime .. "/noctalia-secret-prompts/" .. id
end

-- "ok\n<value>", "notok" or "cancel"; read and removed by the client.
function M.reply(id, result, value)
  local dir = M.promptDir(id)
  if dir == nil then
    return false
  end
  local content = result
  if result == "ok" then
    content = "ok\n" .. (value or "")
  end
  local ok = noctalia.writeFile(dir .. "/reply", content)
  return ok == true
end

return M
