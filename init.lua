-- Copyright 2022 Amy de Buitléir. See LICENSE.

--[[ This comment is for LuaDoc.
---
-- TODO: Put description here
module('lsp')]]

local M = {}

M.keys = {}

local CTRL, ALT, CMD, SHIFT = 'ctrl+', 'alt+', 'cmd+', 'shift+'
if CURSES then
  ALT = 'meta+'
end

local current_key_map = M.keys
local current_tip = ''
local hydra_active = false

--
-- Utility functions
--

local function pretty_key(c)
  if c == ' ' then
    return 'space'
  end
  if c == '\t' then
    return 'tab'
  end
  if c == '\n' then
    return 'enter'
  end
  return c
end

-- Adapted from https://stackoverflow.com/a/42062321/663299
function M.show_table(node)
    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for _,_ in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k,v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then

                if string.find(output_str,"}",output_str:len()) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str,"\n",output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output,output_str)
                output_str = ""

                local key
                if type(k) == "number" or type(k) == "boolean" then
                    key = "["..tostring(k).."]"
                else
                    key = "['"..tostring(k).."']"
                end

                if type(v) == "number" or type(v) == "boolean" then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = "..tostring(v)
                elseif type(v) == "table" then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = {\n"
                    table.insert(stack,node)
                    table.insert(stack,v)
                    cache[node] = cur_index+1
                    break
                else
                    local v_str = tostring(v)
                    v_str = string.gsub(v_str, '\n', '<ret>')
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = '"..v_str.."'"
                end

                if cur_index == size then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if cur_index == size then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if size == 0 then
            output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
        end

        if #stack > 0 then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
    table.insert(output,output_str)
    output_str = table.concat(output)

    return output_str
end

function M.print_keys()
  ui.print("---------------")
  ui.print("Key Definitions")
  ui.print("---------------")
  ui.print(M.show_table(M.keys))
end

--
-- Functions to define a hydra
--

function M.bind(h, t)
  if t.key == nil then
    error('[hydra] missing "key" field' .. M.show_table(t))
  end

  if t.action == nil then
    error('[hydra] missing "action" field' .. M.show_table(t))
  end

  if t.help == nil then
    error('[hydra] missing "help" field' .. M.show_table(t))
  end

  h.help[#h.help+1] = pretty_key(t.key) .. ') ' .. t.help
  h.action[t.key] = { help=t.help, action=t.action, persistent=t.persistent }

  if type(t.action) == 'table' then
    local tip = table.concat(t.action.help, '\n')
    if t.help then
      tip = t.help .. '\n' .. tip
    end
    h.action[t.key].tip = tip
  end
end

local function add_binding(h, t)
  _ = assert(t.key, '[hydra] missing "key" field')

  if h.action[t.key] then
    error('[hydra] WARNING: duplicate binding for key: ' .. pretty_key(t.key) .. ' "' .. t.help .. '"')
  else
    M.bind(h, t)
  end
end

function M.create(t)
  if type(t) ~= 'table' then
    error('[hydra] "create" expected a table')
  end

  local result = { help={}, action={} }

  if t.help then
    result.help[#result.help+1] = t.help
  end

  for _,v in pairs(t) do
    add_binding(result, v)
  end

  return result
end

--
-- Functions for reacting to keypress events
--

local function start_hydra(key_map)
  current_key_map = key_map.action
  hydra_active = true
  current_tip = key_map.tip
  view:call_tip_show(buffer.current_pos, current_tip)
end

local function maintain_hydra()
  view:call_tip_show(buffer.current_pos, current_tip)
end

local function reset_hydra()
  current_key_map = M.keys
  hydra_active = false
  view:call_tip_cancel()
end

local function run(action)
  -- temporarily disable hydra
  local current_key_map_before = current_key_map
  local hydra_active_before = hydra_active
  current_key_map = nil
  hydra_active = false
  view:call_tip_cancel()

  -- run the action
  action()

  -- re-enable hydra
  current_key_map = current_key_map_before
  hydra_active = hydra_active_before
end

local function run_hydra(key_map)
  local action = key_map.action

  if type(action) == 'table' then
    start_hydra(key_map)
    return
  else
    -- invoke the action mapped to this key
    run(action)
    -- should the hydra stay active?
    if key_map.persistent then
      maintain_hydra()
    else
      reset_hydra()
    end
    return
  end
end

local function handle_key_seq(key_seq)
  -- print('handling', key_seq)
  local active_key_map = nil

  if current_key_map.action ~= nil then
    active_key_map = current_key_map.action[key_seq]
  end

  if active_key_map == nil then
    -- An unexpected key cancels any active hydra
    if hydra_active then
      reset_hydra()
    end
    -- Let Textadept or another module handle the key
    return
  else
    run_hydra(active_key_map)
    -- We've handled the key, no need for Textadept or another module to act
    return true
  end
end

--
-- Main code for module
--

events.connect(events.INITIALIZED, function()
  reset_hydra()
end)

events.connect(events.KEYPRESS, function(key_seq)
  return handle_key_seq(key_seq)
end, 1)

return M
