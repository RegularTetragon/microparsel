#!/usr/bin/lua
local P = require("microparsel")

tests = {}

function tests:any()
    assert(P.any:parse("abc") == "a")
end

function tests:empty()
    assert(P.empty:parse("abc") == nil)
end

function tests:endOfStream()
    assert(P.endOfStream:parse("") == "")
end

function tests:anyFail()
    local success, message = pcall(function()P.any:parse("")end)
    assert (not success)
end

function tests:endOfStreamFail()
    local success, message = pcall(function()P.endOfStream:parse("abc")end)
    assert (not success)
end

function tests:chain()
    P.any:chain(
        function(a)
            return P.empty
        end
    ):parse("b")
end

function tests:parserRight()
    assert(P.any:right(P.any):parse("ab") == "b")
end

function tests:parserRightRFail()
    local success, message = pcall(function()P.any:right(P.endOfStream):parse("ab")end)
    assert(not success)
end

function tests:parserRightLFail()
    local success, message = pcall(function()P.any:right(P.any):parse("")end)
    assert(not success)
end

function tests:parserLeft()
    assert(P.any:left(P.any):parse("ab") == "a")
end

function tests:parserLeftRFail()
    local success, message = pcall(function()P.any:left(P.endOfStream):parse("ab")end)
    assert(not success)
end

function tests:parserRightLFail()
    local success, message = pcall(function()P.any:left(P.any):parse("")end)
    assert(not success)
end

function tests:bracketed()
    local parser = P.match("{"):right(P.match("[^}]+")):left(P.match("}"))
    local result = parser:parse("{abcdef}")
    assert(result == "abcdef")
end

function tests:bracketed_ops()
    local parser = P.match("{") >> P.match("[^}]+") << P.match("}")
    local result = parser:parse("{abcdef}")
    assert(result == "abcdef")
end

function tests:bracketed_ops_51_compatible()
    local parser = P.match("{") / P.match("[^}]+") * P.match("}")
    local result = parser:parse("{abcdef}")
    assert(result == "abcdef")
end

function tests:many()
    local parser = P.many(P.match("[A-Za-z]+ "))
    local result = parser:parse("hello world ")
    assert(result[1] == "hello ")
    assert(result[2] == "world ")
end

function tests:choiceL()
    local parser = P.choice(P.match("abc"), P.match("jkl"))
    assert(parser:parse("abc") == "abc")
end

function tests:choiceR()
    local parser = P.choice(P.match("abc"), P.match("jkl"))
    assert(parser:parse("jkl") == "jkl")
end

function tests:choiceNeither()
    local parser = P.choice(P.match("abc"), P.match("jkl"))
    assert(not parser:tryParse("heyyy"))
end

function tests:sepBy()
    local parser = P.sepBy(P.match(","), P.match("[A-Za-z]+"))
    local result = parser:parse("a,b,c")
    assert(result[1] == "a" and result[2] == "b" and result[3] == "c" and result[4] == nil)
end

function tests:sepByEmpty()
    local parser = P.sepBy(P.match(","), P.match("[A-Za-z]+"))
    local result = parser:parse("")
    assert(result[1] == nil)
end

function tests:sepBy1()
    local parser = P.sepBy1(P.match(","), P.match("[A-Za-z]+"))
    local result = parser:parse("a,b,c")
    assert(result[1] == "a" and result[2] == "b" and result[3] == "c" and result[4] == nil)
end

function tests:sepBy1Fail()
    local parser = P.sepBy1(P.match(","), P.match("[A-Za-z]+"))
    local result = parser:tryParse("")
    assert(not result)
end

function tests:value()
    local parser = (P.match("true") >> P.value(true)) + (P.match("false") >> P.value(false))
    assert(parser:parse("true") == true)
    assert(parser:parse("false") == false)
end

function tests:map()
    local parser = P.match("[A-Za-z]+")
    local mappedParser = parser:map(function(v) return #v end)
    assert(mappedParser:parse("hello") == 5)
end
local failures = {}

for k, test in pairs(tests) do
    local success, error = xpcall(
        function() 
            test()
            print("Test passed: "..k)
        end,
        function(msg)
            print("Test failed: "..k)
            failures[k] = tostring(msg) .. "\n" .. debug.traceback() 
        end
    )
end

if next(failures) ~= nil then
    print("====FAILURE SUMMARY====")
    for k,v in pairs(failures) do
        print(k .. "\n" .. v .. "\n" .. "----" )
    end
end