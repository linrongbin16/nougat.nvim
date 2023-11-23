local on_event = require("nougat.util").on_event

local mod = {}

---@class NougatCacheStore
---@field [integer] table|table<integer, table>

---@type table<'buf'|'win'|'tab', table<string, NougatCacheStore>>
local registry = { buf = {}, win = {}, tab = {} }

---@param store NougatCacheStore
---@param id integer
local function clear_store(store, id)
  local cache = store[id]
  if cache then
    for key in pairs(cache) do
      cache[key] = nil
    end
  end
end

local default_initial_value = {}

---@param cache_type 'buf'|'win'|'tab'
---@param name string
---@param initial_value? table
---@return NougatCacheStore cache_store
function mod.create_store(cache_type, name, initial_value)
  initial_value = initial_value or default_initial_value

  if registry[cache_type][name] then
    local store = registry[cache_type][name]
    if store._initial_value ~= initial_value then
      error("cache store already created with different initial_value")
    end
    return store
  end

  ---@class NougatCacheStore
  local store = setmetatable({
    type = cache_type,
    name = name,
    clear = clear_store,
    _initial_value = initial_value,
  }, {
    __index = function(storage, id)
      return rawset(
        storage,
        id,
        setmetatable(vim.deepcopy(initial_value), {
          __index = function(cache, key)
            if type(key) == "number" then
              return rawset(cache, key, vim.deepcopy(initial_value))[key]
            end
            if initial_value[key] ~= nil then
              return rawset(cache, key, vim.deepcopy(initial_value[key]))[key]
            end
          end,
        })
      )[id]
    end,
  })

  registry[cache_type][name] = store

  return store
end

---@param type 'buf'|'win'|'tab'
---@param name string
---@param id integer
---@return any
function mod.get(type, name, id)
  return registry[type][name][id]
end

---@param type 'buf'|'win'|'tab'
---@param id integer
local function clear_cache(type, id)
  for _, storage in pairs(registry[type]) do
    storage[id] = nil
  end
end

on_event("BufWipeout", function(info)
  local bufnr = info.buf
  vim.schedule(function()
    clear_cache("buf", bufnr)
  end)
end)

on_event("WinClosed", function(info)
  local winid = tonumber(info.match)
  if winid then
    vim.schedule(function()
      clear_cache("win", winid)
    end)
  end
end)

on_event("TabClosed", function()
  vim.schedule(function()
    local active_tabid = {}
    for _, tabid in ipairs(vim.api.nvim_list_tabpages()) do
      active_tabid[tabid] = true
    end

    for _, storage in pairs(registry.tab) do
      for tabid in pairs(storage) do
        if not active_tabid[tabid] then
          storage[tabid] = nil
        end
      end
    end
  end)
end)

return mod
