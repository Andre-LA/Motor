-- TODO: the documentation is TOTALLY deprecated,
-- I will update when Motor becomes stable
-- (this means: at least one complete game made in Motor)

--- motor: An ECS lua library.
-- check @{main.lua|main.lua example}
-- @see new
-- @license MIT
-- @author André Luiz Alvares
-- @module motor

local motor = {}

local _floor = math.floor
local _table_remove = table.remove
local _assert = assert
local _type = type

local function check_value_type (value_to_check, type_expected, arg_name, arg_number)
  local value_type = _type(value_to_check)
  _assert(
    value_type == type_expected,
    "Motor problem: \n\t*"
    .. type_expected .. "* expected in the #" .. arg_number .. " argument ('" .. arg_name .. "'), got *"
    .. value_type .. "*"
  )
  return value_to_check
end

local function check_table_values_type (table_to_check, type_expected, arg_name, arg_number)
  local check_iter = function()
    local table_to_check_len = #table_to_check
    local type_expected_len = #type_expected
    local iterator_count = 0

    if _type(type_expected) == "table" then
      local type_expected_index = 0

      return function ()
        iterator_count = iterator_count + 1
        if iterator_count <= table_to_check_len then
          type_expected_index = type_expected_index <= type_expected_len
            and type_expected_index + 1
            or 1

          return table_to_check[iterator_count], type_expected[type_expected_index], iterator_count
        end
      end
    else
      return function()
        iterator_count = iterator_count + 1
        if iterator_count <= table_to_check_len then
          return table_to_check[iterator_count], type_expected, iterator_count
        end
      end
    end
  end

  for table_value_to_check, value_type_expected, table_value_to_check_index in check_iter() do
    local value_type = _type(table_value_to_check)
    _assert(
      value_type == value_type_expected,
      "Motor problem: \n\t*"
      .. value_type_expected .. "* expected in the #" .. table_value_to_check_index
      .. " index of the table in the #" .. arg_number .. " argument ('" .. arg_name .. "'), got *" .. value_type .. "*"
    )
  end

  return table_to_check
end

local function prepare_component_constructors(component_constructors)
  -- note: in this scope, "cc" means "Component Constructor(s)"

  local function _check_cc_value(cc, key, type_expected)
    local cc_value = _assert(cc[key], "Motor problem: '" .. key .. "' key expected in a component constructor")
    local cc_value_type = _type(cc_value)

    _assert(
      cc_value_type == type_expected,
      "Motor problem: '"
        .. type_expected .. "' type expected in '"
        .. key .. "' key in a component constructor, got '"
        .. cc_value_type .. "'"
    )

    return cc_value
  end

  local prepared_cc = {}

  for i = 1, #component_constructors do
    local cc = component_constructors[i]

    local cc_name = _check_cc_value(cc, "name", "string")
    local cc_constructor = _check_cc_value(cc, "constructor", "function")

    prepared_cc[cc_name] = cc_constructor
  end

  return prepared_cc
end

--- motor constructor
-- @function new
-- @tparam table component_constructors
-- @tparam table systems
-- @treturn table new motor instance
-- @usage
-- local universe = motor.new_universe(
--   { -- components constructors:
--     position = function(v) return {x = v.x, y = v.y} end,
--     velocity = function(v) return {x = v.x, y = v.y} end,
--     mesh     = function(v) return {value = love.graphics.newMesh(v.vertices, v.mode, v.usage)} end,
--     drawable = function(v, e) return {drawable = e[v.drawable].value} end,
--   },
--   { -- systems (will be executed in the following order):
--     require ("example_systems/move_system"),
--     require ("example_systems/draw_drawable_system"),
--   }
-- )
function motor.new_universe(component_constructors, systems)
  check_value_type(component_constructors, "table", "component_constructors", 1)
  check_value_type(systems, "table", "systems", 2)
  check_table_values_type(component_constructors, "table", "component_constructors", 1)

  local new = {
    -- registered component_constructors and systems
    component_constructors = prepare_component_constructors(component_constructors),
    systems = check_table_values_type(systems, "table", "component_constructors", 1),
    worlds = {},
    last_world_id = 0,
  }

  return new
end

--- @todo doc this!
function motor.new_system(_name, _filter)
  local new_system = {
    name = _name,
    filter = _filter,
  }

  new_system.__index = new_system

  new_system.new = function(_world)
    local system_constructor = {
      world = _world,
      entities = {},
    }
    setmetatable(system_constructor, new_system)
    return system_constructor
  end

  return new_system
end

local function get_table_subkey(tbl, subkeys)
  local subkeys_count = #subkeys
  local key_value = tbl;

  for k=1, subkeys_count do
    local sub = key_value[subkeys[k]]
    if sub ~= nil then
      key_value = sub
    else
      return
    end
  end

  return key_value
end

local function bin_search_with_key(tbl, keys, target)
  local keys_count = #keys

  local min = 1
  local max = #tbl

  while min <= max do
    local mid = _floor( (min + max)/2 )
    local tbl_mid = tbl[mid]
    local tbl_mid_key_value = keys_count > 1 and get_table_subkey(tbl_mid, keys) or tbl_mid[keys[1]]

    if tbl_mid_key_value == target then
      return mid
    elseif target < tbl_mid_key_value then
      max = mid - 1
    else
      min = mid + 1
    end
  end
end

--- calls a function (if it exists) in all systems in all @{world|worlds}
-- @function call
-- @usage
-- function love.update(dt)
--    motor:call("update", dt)
-- end
-- @tparam string function_name the name of function to be called
-- @param ... parameters of the function to be called.
function motor.call(universe, function_name, ...)
  check_value_type(function_name, "string", "function_name", 2)

  for w=1, #universe.worlds do
    local world = universe.worlds[w]

    for s=1, #world.systems do
      local system = world.systems[s]

      if system[function_name] then
        system[function_name](system, ...)
      end
    end
  end
end

--- World Functions
-- @section World

--- creates a new @{world} inside motor instance
-- @usage
-- local main_world_id, main_world_ref = motor:new_world({"move", "drawer"})
-- @see world
-- @function new_world
-- @tparam {string} systems_names each string is a system to be processed in the @{world}
-- @treturn number the id of the created @{world},
-- @treturn world the new world
function motor.new_world(universe, systems_names)
  check_value_type(systems_names, "table", "systems_names", 2)
  check_table_values_type(systems_names, "string", "systems_names", 2)

  universe.last_world_id = universe.last_world_id + 1

  universe.worlds[#universe.worlds+1] = {
    id       = universe.last_world_id,
    last_id  = 0,
    systems  = {},
    entities = {},
  }

  local new_world = universe.worlds[universe.last_world_id]

  for s=1, #universe.systems do
    for sn=1, #systems_names do
      if systems_names[sn] == universe.systems[s].name then
        new_world.systems[#new_world.systems+1] = universe.systems[s].new(new_world)
        break
      end
    end
  end

  return new_world
end

--- returns the @{world} of this id
-- @usage
-- local world_ref = motor:get_world(main_world_id)
-- @see world
-- @function get_world
-- @number world_id (integer) id of the @{world} to be obtained
-- @treturn world world reference
function motor.get_world (universe, world_id)
  return universe.worlds[bin_search_with_key(universe.worlds, {"id"}, world_id)]
end

local function update_systems_entities_on_add(world, entity)
  for s=1, #world.systems do
    local system = world.systems[s]

    if system.filter(entity) and not (bin_search_with_key(system.entities, {'id'}, entity.id)) then
      system.entities[#system.entities+1] = entity
    end
  end
end

local function update_systems_entities_on_remove(world, entity_id)
  for s=1, #world.systems do
    local system = world.systems[s]

    local entity_index_in_system = bin_search_with_key(system.entities, {"id"}, entity_id)

    if entity_index_in_system then
      _table_remove(system.entities, entity_index_in_system)
    end
  end
end

--- Entities Functions
-- @section Entity

local function create_entity(world, parent_id)
  -- incrementing last entity id of this world
  world.last_id = world.last_id + 1

  -- create the entity
  world.entities[#world.entities+1] = {
    id = world.last_id,
    parent_id = parent_id or 0,
    children = {},
  }

  return world.entities[#world.entities]
end

function motor.set_parent(world, entity, parent_id)
  -- if parent_id is nil, then entity will not have a parent

  if parent_id then
    -- register child to parent
    local parent_entity = motor.get_entity(world, parent_id)
    parent_entity.children[#parent_entity.children] = entity.id

  -- if the entity currently has a parent, unregister it
  elseif entity.parent_id ~= 0 then
    local parent_entity = motor.get_entity(world, entity.parent)

    for i=1, #parent_entity.children do
      if parent_entity.children[i] == entity.id then
        _table_remove(parent_entity.children, i)
      end
    end
  end

    -- register or unregister (respectively) child's parent
  entity.parent_id = parent_id or 0
end

--- Create an @{entity} in a @{world}
-- @function new_entity
-- @usage
-- local entity_id, entity_ref = motor.new_entity(world_ref)
-- @see entity
-- @see world
-- @tparam world world
-- @tparam[opt=0] number  parent_id optional parent id
-- @treturn number id of the new @{entity}
-- @treturn entity entity created
function motor.new_entity(world, parent_id)
  local new_entity = create_entity(world, parent_id)
  if parent_id then
    motor.set_parent(world, new_entity, parent_id)
  end
  return new_entity
end

--- get a @{entity} with the given key [with the given value]
-- @usage
-- local entity_id, entity_ref = motor.get_entity_by_key(world_ref, "name", "André")
-- @see world
-- @see entity
-- @function get_entity_by_key
-- @tparam world world table
-- @tparam string key
-- @tparam[opt] value value
-- @treturn number entity id
-- @treturn entity entity
function motor.get_entity (world, keys, value, use_bin_search)
  -- check values
  check_value_type(keys, "table", "keys", 2)
  check_table_values_type(keys, "string", "keys", 2)

  local keys_count = #keys

  -- use bin search to find the entity
  if use_bin_search then
    return world.entities[bin_search_with_key(world.entities, keys, value)]
  else
    -- for each entity
    for i=1, #world.entities do
      -- get entity reference
      local entity = world.entities[i]

      -- get the value of key(s)
      local entity_key_value = keys_count > 1 and get_table_subkey(entity, keys) or entity[keys[1]]

      -- if this key(s) exists and is equals to value (if value is not nil),
      -- then return the entity
      if entity_key_value and (value ~= nil and entity_key_value == value or true) then
        return entity
      end
    end
  end
end

--- set multiple components in an @{entity}
-- @usage
-- -- creating the world and getting a reference of it
-- main_world_id, world_ref = motor:new_world({"move", "drawer"})
--
-- -- creating one entity and getting a reference of it
-- entity_id, entity_ref = motor.new_entity(world_ref)
--
-- -- setting the entity components
-- motor:set_components(world_ref, entity_ref, {
--     "position", {x = 5, y = 5},
--     "velocity", {x = 1, y = 1},
--     "mesh"    , {vertices = {{-50, -50}, {50, -50}, {00, 50}}},
-- })
-- @function set_components
-- @tparam world world table (not world id)
-- @tparam entity entity to be modified
-- @tparam table component_names_and_values component names and values in pairs
function motor.set_components (universe, world, entity, component_names_and_values)
  for cnavi=1, #component_names_and_values, 2 do -- cnavi: Component Name And Value Index
    local component_name = component_names_and_values[cnavi]

    if component_name == "id" or component_name == "children" then
      print(
        "component pair ignored: '" .. component_name
          .. "' because " .. component_name .. " not should be modified"
      )
    else
      local component_constructor = _assert(
        universe.component_constructors[component_name],
        "component constructor of '" .. component_name .. "' not found"
      )

      entity[component_name] = component_constructor(component_names_and_values[cnavi+1], world, entity, universe)
    end
  end

  update_systems_entities_on_add(world, entity)
end

--- destroy an @{entity}
-- @usage
-- motor.destroy_entity(world_ref, hero_id)
-- @function destroy_entity
-- @tparam world world table (not world id)
-- @tparam number entity_id id of the @{entity} to be destroyed
function motor.destroy_entity(world, entity_id)
  local entity_id_index = bin_search_with_key(world.entities, {"id"}, entity_id)
  _table_remove(world.entities, entity_id_index)
  update_systems_entities_on_remove(world, entity_id)
end

return motor

--- (Table) Structures
-- @section structures

--- World structure
-- @tfield number id id of this @{world}
-- @tfield number last_id used to generate entity ids, stores the id of the last entity
-- @tfield {system} the systems that will be processed in this @{world}. It is automatically generated by systems_names
-- @tfield {entity} entities
-- @table world

--- Entity structure:
-- an entity is just a table with id and components
-- @tfield number id id of the entity
-- @tfield number parent_id parent's id, if there is none, it will be 0.
-- @tfield table children children ids
-- @tfield table example_component_1
-- @tfield table example_component_2
-- @field ... other components
-- @table entity
