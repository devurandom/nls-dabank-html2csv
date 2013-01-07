#!/usr/bin/lua

package.path = package.path .. ";penlight/lua/?.lua"


local xml = require "pl.xml"
local pretty = require "pl.pretty"


-- trim6 from http://lua-users.org/wiki/StringTrim
function string:trim()
	return self:match('^()%s*$') and '' or self:match('^%s*(.*%S)')
end

function reduce_space(self)
	return self:gsub("&nbsp;", " "):gsub(" +", " "):trim()
end


-- Configuration values:
-- IDX: Absolute index, ROW: Relative to start of city, COL: Column
local DESCRIPTION_IDX = 1
local GENDER_START_COL, GENDER_END_COL = 2, 4
local FIRST_CITY_IDX, NEXT_CITY_ROW = 4, 29
local TOTAL_ROW = 2
local AGES_START_ROW, AGES_END_ROW = 4, 7
local DETAILS_START_ROW, DETAILS_END_ROW = 9, 28


local input
if #arg < 1 then
	input = io.stdin
else
	input = io.open(arg[1])
end

local output
if #arg < 2 then
	output = io.stdout
else
	output = io.open(arg[2], "w+")
end


local contents, err = input:read("*a")
if not contents then
	error(string.format("Could not read file: %s", err))
end


xml.parsehtml = true
local parsed, err = xml.parse(contents)
if not parsed then
	error(string.format("Could not parse html file: %s", err))
end


local e_html = parsed:child_with_name("html") or parsed -- somehow html is not the outermost element...?
local e_body = e_html:child_with_name("body")
local e_table = e_body:child_with_name("table")
local e_tbody = e_table:child_with_name("tbody")
if not e_tbody then
	-- older tables do not contain a tbody
	e_tbody = e_table
	DESCRIPTION_IDX = DESCRIPTION_IDX + 1
	FIRST_CITY_IDX = FIRST_CITY_IDX + 1
end


local cities = {}
local genders = {}
local agegroups = {}
local detailed_agegroups = {}


local description_tr = e_tbody[DESCRIPTION_IDX]
for i = GENDER_START_COL, GENDER_END_COL do
	local gender, width = description_tr[i]:get_text(), description_tr[i]:get_attribs().colspan
	gender = reduce_space(gender)
	width = tonumber(width)
	table.insert(genders, {gender = gender, width = width})
end


local city_idx = FIRST_CITY_IDX
local city_tr = e_tbody[city_idx]

while city_tr do
	local city_td = city_tr[1]
	local city_text = city_td:get_text()
	if not city_text then
		error("BUG")
	end

	local city_number, city_name = city_text:match("^(%d+)%s+(.*)")
	if not city_number or not city_name then
		error(string.format("Failed to parse city blurbs: %s", city_text))
	end

	city_name = reduce_space(city_name)
	city_number = tonumber(city_number)

	local city = {number = city_number, name = city_name}

	local function get_data(tr)
		local values = {}
		local col = GENDER_START_COL
		for i = 1, #genders do
			local value = tr[col]:get_text()
			value = tonumber(value)
			table.insert(values, value)
			col = col + genders[i].width
		end
		return values
	end

	local function parse_line(i)
		local tr = e_tbody[i]
		local agegroup = tr[1]:get_text()
		agegroup = reduce_space(agegroup)
		return agegroup, get_data(tr)
	end

	local _, data = parse_line(city_idx + TOTAL_ROW)
	city.total = data

	city.ages = {}
	for i = city_idx + AGES_START_ROW, city_idx + AGES_END_ROW do
		local agegroup, data = parse_line(i)
		city.ages[agegroup] = data
		if not agegroups[agegroup] then
			assert(city_idx == FIRST_CITY_IDX)
			agegroups[agegroup] = true
			table.insert(agegroups, agegroup)
		end
	end

	city.details = {}
	for i = city_idx + DETAILS_START_ROW, city_idx + DETAILS_END_ROW do
		local agegroup, data = parse_line(i)
		city.details[agegroup] = data
		if not detailed_agegroups[agegroup] then
			assert(city_idx == FIRST_CITY_IDX)
			detailed_agegroups[agegroup] = true
			table.insert(detailed_agegroups, agegroup)
		end
	end

	table.insert(cities, city)

	city_idx = city_idx + NEXT_CITY_ROW
	city_tr = e_tbody[city_idx]
end


output:write("Number:Name")
for _,gender in ipairs(genders) do
	output:write(":total -- "..gender.gender)
end
for _,agegroup in ipairs(agegroups) do
	for _,gender in ipairs(genders) do
		output:write(":"..agegroup.." -- "..gender.gender)
	end
end
for _,agegroup in ipairs(detailed_agegroups) do
	for _,gender in ipairs(genders) do
		output:write(":"..agegroup.." -- "..gender.gender)
	end
end
output:write("\n")


for _,city in ipairs(cities) do
	output:write(string.format("%d:%s", city.number, city.name))

	local function print_data(data)
		for i = 1, #genders do
			local item = data[i]
			if not item then
				output:write(":-")
			else
				output:write(string.format(":%d", item))
			end
		end
	end

	print_data(city.total)

	for _,idx in ipairs(agegroups) do
		print_data(city.ages[idx])
	end

	for _,idx in ipairs(detailed_agegroups) do
		print_data(city.details[idx])
	end

	output:write("\n")
end
