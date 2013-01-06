#!/usr/bin/lua

--[[
	Converts output of NLS DABANK-PC HTML-Interface to CSV
		(NLS: Niedersächsisches Landesamt für Statistik)
	Sample: http://www.stadt-walsrode.de/media/custom/352_551_1.HTML
]]

package.path = package.path .. ";penlight/lua/?.lua"

local xml = require "pl.xml"
local pretty = require "pl.pretty"

-- trim6 from http://lua-users.org/wiki/StringTrim
function string.trim(s)
	return s:match'^()%s*$' and '' or s:match'^%s*(.*%S)'
end


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


local cities = {}

local city_idx = 4
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

	city_name = city_name:trim():gsub("&nbsp;", ""):gsub("  ", " ")
	city_number = tonumber(city_number)

	local city = {number = city_number, name = city_name}

	local function get_data(tr)
		local total, male, female = tr[2]:get_text(), tr[5]:get_text(), tr[7]:get_text()
		total, male, female = tonumber(total), tonumber(male), tonumber(female)
		return total, male, female
	end

	local function parse_line(i)
		local tr = e_tbody[i]
		local agegroup = tr[1]:get_text()
		agegroup = agegroup:trim():gsub("&nbsp;", ""):gsub("  ", " ")

		return agegroup, {get_data(tr)}
	end

	local _, data = parse_line(city_idx + 2)
	city.total = data

	city.ages = {}
	for i = city_idx + 4, city_idx + 7 do
		local agegroup, data = parse_line(i)
		city.ages[agegroup] = data
	end

	city.details = {}
	for i = city_idx + 9, city_idx + 28 do
		local agegroup, data = parse_line(i)
		city.details[agegroup] = data
	end

	table.insert(cities, city)

	city_idx = city_idx + 29
	city_tr = e_tbody[city_idx]
end


local agegroups = {
	"0 - 15",
	"15 - 60",
	"60 - 65",
	"65 und mehr",
}

local detailed_agegroups = {
	"0 - 3",
	"3 - 5",
	"5 - 6",
	"6 - 10",
	"10 - 15",
	"15 - 18",
	"18 - 20",
	"20 - 25",
	"25 - 30",
	"30 - 35",
	"35 - 40",
	"40 - 45",
	"45 - 50",
	"50 - 55",
	"55 - 60",
	"60 - 63",
	"63 - 65",
	"65 - 70",
	"70 - 75",
	"75 und mehr",
}


output:write("Number:Name")
for _,gender in ipairs{"total", "male", "female"} do
	output:write(":total -- "..gender)
end
for _,agegroup in ipairs(agegroups) do
	for _,gender in ipairs{"total", "male", "female"} do
		output:write(":"..agegroup.." -- "..gender)
	end
end
for _,agegroup in ipairs(detailed_agegroups) do
	for _,gender in ipairs{"total", "male", "female"} do
		output:write(":"..agegroup.." -- "..gender)
	end
end
output:write("\n")


for _,city in ipairs(cities) do
	output:write(string.format("%d:%s", city.number, city.name))

	local function print_data(data)
		for i = 1, 3 do
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
