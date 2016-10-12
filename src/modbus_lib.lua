local modbustcp = require 'modbustcp'
local bit32 = require 'bit32'
local log = require('log') 

local modbusdev = {}
local modbus_lib = {}
local LOGNAME = "MODBUS"

local function check_error(err)
	if err then
		log(LOGNAME, "ERROR", "(MODBUS) An error has occured - %s", err) 
	end
end

local function check_read_value(data, err, length, decoder)
	local res
	if not err then
		res={string.unpack(data,string.format("<%s%s", decoder, length))}
		table.remove(res,1)
	else
		check_error(err)
	end
	return res, err
end

function modbus_lib.init(maxsocket, timeout, logName) 
	local cfg = {maxsocket = maxsocket, timeout = timeout}
	modbusdev = modbustcp:new('TCP', cfg)
	LOGNAME = logName
end

function modbus_lib.close()
	modbusdev:close()
end

function modbus_lib.writeCoil(hostAddress, hostPort, address, value) 
	local realValue
	local val = tonumber(value)
	if val then
		if val > 0 then
			realValue = true
		else 
			realValue = false
		end 
		_,err = modbusdev:writeSingleCoil(hostAddress, hostPort, 1, address, realValue)
		check_error(err)	
	end
end

function modbus_lib.writeFloat(hostAddress, hostPort, address, value) 
	--local realAddress = 9000 + (address * 2);
	local pack = string.pack("<f1", value)
	_,err = modbusdev:writeMultipleRegisters(hostAddress, hostPort, 1, address, pack)
	check_error(err)
end

function modbus_lib.writeLong(hostAddress, hostPort, address, value) 
	--local realAddress = 5000 + (address * 2);
	local pack = string.pack("<l1", value)
	_,err = modbusdev:writeMultipleRegisters(hostAddress, hostPort, 1, address, pack)
	check_error(err)
end

function modbus_lib.writeRegister(hostAddress, hostPort, address, value) 
	_,err = modbusdev:writeSingleRegister(hostAddress, hostPort, 1, address, value)
	check_error(err)
end

function modbus_lib.readHoldingRegister(hostAddress, hostPort, address, length)
	local data,err = modbusdev:readHoldingRegisters(hostAddress, hostPort, 1, address, length)
	return check_read_value(data, err, length, 'h')
end

function modbus_lib.readInputRegisters(hostAddress, hostPort, address, length)
	local data,err = modbusdev:readInputRegisters(hostAddress, hostPort, 1, address, length)
	return check_read_value(data, err, length, 'h')
end

function modbus_lib.readCoils(hostAddress, hostPort, address)
	local data,err = modbusdev:readCoils(hostAddress, hostPort, 1, address, 1)
	return check_read_value(data, err, 1, 'b')
end

function modbus_lib.readDiscreteInputs(hostAddress, hostPort, address)
	local data,err = modbusdev:readDiscreteInputs(hostAddress, hostPort, 1, address, 1)
	return check_read_value(data, err, 1, 'b')
end

function modbus_lib.readLong(hostAddress, hostPort, address, length)
	local res
	local data,err = modbusdev:readHoldingRegisters(hostAddress, hostPort, 1, address, length)
	if not err then
		res={string.unpack(data,string.format("<l%d", length))}
		table.remove(res,1)
	else
		check_error(err)
	end
	return res, err
end

function modbus_lib.readFloat(hostAddress, hostPort, address, length)
	local res
	local data,err = modbusdev:readHoldingRegisters(hostAddress, hostPort, 1, address, length)
	if not err then
		res={string.unpack(data,string.format("<f%d", length))}
		table.remove(res,1)
	else
		check_error(err)
	end
	return res, err
end

return modbus_lib