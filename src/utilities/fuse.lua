local function mkset(array)
  local set = {}
  for _,flag in ipairs(array) do
    set[flag] = true
  end
  return set
end

local assert = function(...)
  local value,err = ...
  if not value then
    error(err, 2)
  else
    return ...
  end
end


local function splitpath(path)
  local elements = {}
  for element in path:gmatch("[^/]+") do
    table.insert(elements, element)
  end
  return elements
end

local function keys(tbl)
  local ret = {}
  if tbl then
  for k, _ in pairs(tbl) do
      ret[#ret+1] = k
    end
  end
  return ret
end

return {
  mkset = mkset,
  assert = assert,
  splitpath = splitpath,
  keys = keys,
}
