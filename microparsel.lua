--A single file, Lua 5.1 compatible parsing library
local P = {}

local Either = {}
do -- Define Either
    local Left = {}
    local LeftMT = {
        __index = Left,
        __tostring = function(self)
            return "Left("..tostring(self.value)..")"
        end
    }
    local Right = {}
    local RightMT = {
        __index = Right,
        __tostring = function(self)
            return "Right("..tostring(self.value)..")"
        end
    }

    function Left.new(value)
        return setmetatable({value=value}, LeftMT)
    end

    function Left:bind(operation)
        return self
    end

    function Left:unwrap()
        error(self.value)
    end

    function Left:isRight()
        return false
    end

    function Left:map(_)
        return self
    end

    function Right.new(value)
        return setmetatable({value=value}, RightMT)
    end

    function Right:unwrap()
        return self.value
    end

    function Right:isRight()
        return true
    end

    function Right:map(f)
        return Right.new(f(self.value))
    end

    function Either.left(value)
        return Left.new(value)
    end

    function Either.right(value)
        return Right.new(value)
    end
end

local Parser = {}
local ParserMT = {__index=Parser}
local ParserError = {}

--Helper function for adding a value to a list
local function cons(value)
    return function(xs)
        local result = {}
        table.insert(result, value)
        for _, x in pairs(xs) do
            table.insert(result, x)
        end
        return result
    end
end

do -- Define Parser wrapper
    local ParserErrorMT = {__index=ParserError}

    function ParserError.new(expected, received)
        return setmetatable({
            expected = expected,
            received = received
        }, ParserErrorMT)
    end

    function ParserErrorMT:__tostring()
        return "Expected " .. self.expected .. " but received " .. self.received
    end

    --Construct a parser from a raw parsing function
    function Parser.new(parseFunc)
        -- parseFunc :: string -> string, a, number
        --  Takes a function which accepts a string,
        --  Parses some of it, puts the remainder string
        --  in as the first return value, the result
        --  of the parsing into the second return value,
        --  and the number of characters consumed as
        --  the third return value.
        return setmetatable({
            parseFunc = parseFunc
        }, ParserMT)
    end

    function Parser.indexToLineCol(str, index)
        local line, char = 1, 1
        for i = 1, index do
            local c = str:sub(i,i)
            if c == "\n" then
                line = line + 1
                char = 1
            else
                char = char + 1
            end
        end
        return line, char
    end

    --Take a string and parse it. If it fails, a descriptive
    --error message will be thrown.
    function Parser:parse(str)
        local remainder, result, consumed = self.parseFunc(str)
        if result:isRight() then
            return result:unwrap()
        else
            local line, col = Parser.indexToLineCol(str, consumed)

            error("(" .. line .. ":" .. col .. ") " .. tostring(result.value) )
        end
    end

    function Parser:tryParse(str)
        local success, message = pcall(function() return self:parse(str) end)
        return success, message
    end

    --Take a function which takes a value and produces a parser.
    --First consume using self, pass the result to f, and then
    --consume using the result of f.
    function Parser:chain(f)
        return Parser.new(
            function(input)
                local lremainder, lresult, lconsumed = self.parseFunc(input)
                if lresult:isRight() then
                    rremainder, rresult, rconsumed = f(lresult:unwrap()).parseFunc(lremainder)
                    return rremainder, rresult, lconsumed + rconsumed
                end
                return lremainder, lresult, lconsumed
            end
        )
    end

    function Parser:map(f)
        return Parser.new(
            function(input)
                local remainder, result, consumed = self.parseFunc(input)
                return remainder, result:map(f), consumed
            end
        )
    end

    --Take another parser, consume its input and take its result,
    --ignore the result of self.
    function Parser:right(next)
        return self:chain(function (value) return next end)
    end

    --Take another parser, consume its input but throw out its result,
    --The result of the combined parsers is the one the method is called
    --on.
    function Parser:left(next)
        return self:chain(function(value) return next:result(value) end)
    end

    --Parses using itself, throws out the result and returns a value.
    function Parser:result(value)
        return Parser.new(
            function(input)
                local remainder, result, consumed = self.parseFunc(input)
                if result:isRight() then
                    return remainder, Either.right(value), consumed
                else
                    return remainder, result, consumed
                end
            end
        )
    end

    P.Parser = Parser
end

do -- Define simple parsers and combinators
    -- Parse any single character
    P.any = Parser.new(
        function(input)
            if #input == 0 then
                return "", Either.left(ParserError.new("any character", "end of stream")), 0
            else
                return string.sub(input, 2, -1), Either.right(string.sub(input, 1, 1)), 1
            end
        end
    )

    -- Parse only an empty string
    P.endOfStream = Parser.new(
        function(input)
            if #input == 0 then
                return "", Either.right(""), 0
            else
                return input, Either.left(ParserError.new("end of stream", input)), 0
            end
        end
    )

    -- Always passes, consumes nothing, returns nil
    P.empty = Parser.new(
        function(input)
            return input, Either.right(nil), 0
        end
    )

    function P.try(parser)
        return Parser.new(
            function(input)
                remainder, result, consumed = parser.parseFunc(input)
                if result:isRight() then
                    return remainder, result, consumed
                else
                    return input, result, 0
                end
            end
        )
    end

    function P.charPred(description, predicate)
        return P.try(P.any:chain(function(value)
            return Parser.new(function(input)
                if predicate(value) then
                    return input, Either.right(value), 0
                else
                    return input, Either.left(ParserError(description, value)), 0
                end
            end)
        end))
    end

    function P.choice(...)
        parsers = {...}
        return Parser.new(function(input)
            errors = {}
            for _, parser in ipairs(parsers) do
                local remainder, result, consumed = P.try(parser).parseFunc(input)
                if result:isRight() then
                    return remainder, result, consumed
                else
                    table.insert(errors, result.value.expected)
                end
            end
            return input, Either.left(ParserError.new("one of the following: ".. table.concat(errors, ", "), input)), 0
        end)
    end

    function P.match(pattern)
        assert(pattern, "pattern must not be nil")
        return Parser.new(function(input)
            left, right = string.find(input, pattern)
            if left == 1 then
                return string.sub(input, right + 1), Either.right(string.sub(input, left, right)), right - left + 1
            else
                return input, Either.left(ParserError.new("pattern "..pattern, #input > 0 and input or "end of stream")), 0
            end
        end)
    end

    function P.many(parser)
        return Parser.new(
            function(input)
                local results = {}
                local totalConsumed = 0
                while true do
                    local remainder, result, consumed = parser.parseFunc(input)
                    if result:isRight() then
                        totalConsumed = totalConsumed + consumed
                        table.insert(results, result:unwrap())
                    else
                        return input, Either.right(results), totalConsumed
                    end
                    input = remainder
                end
            end
        )
    end

    function P.many1(parser)
        return parser:chain(function(value)
            return P.many(parser):map(cons(value))
        end)
    end

    function P.sequence(...)
        local parsers = {...}
        return Parser.new(
            function(input)
                local results = {}
                local totalConsumed = 0
                for _, parser in pairs(parsers) do
                    local remainder, result, consumed = parser.parseFunc(input)
                    if not result:isRight() then
                        return remainder, result, totalConsumed
                    end
                    table.insert(results, result:unwrap())
                    totalConsumed = totalConsumed + consumed
                    input = remainder
                end
                return input, Either.right(results), totalConsumed
            end
        )
    end

    function P.optional(parser, default)
        return Parser.new(function(input)
            local remainder, result, consumed = parser.parseFunc(input)
            if result.isRight() then
                return remainder, result, consumed
            else
                return input, Either.right(default), 0
            end
        end)
    end

    function P.value(value)
        return P.empty:result(value)
    end

    function P.sepBy(separator, content)
        return P.many(
            content:left(P.optional(separator))
        )
    end

    function P.sepBy1(separator, content)
        return content:left(separator):chain(
            function (result)
                return P.sepBy(separator, content):map(cons(result))
            end
        )
    end

    function P.between(left, right, p)
        return left:right(p):left(right)
    end

    -- Takes a table of mutually recursive parsers and
    -- wraps it in a way which avoids stack overflows.
    function P.language(languageDescriptor)
        local language = {}
        for k, parser in pairs(languageDescriptor) do
            language [k] = function(...)
                local parserArgs = {...}
                parserArgs[1] = language
                return Parser.new(
                    function(input)
                        return parser(table.unpack(parserArgs)).parseFunc(input)
                    end
                )
            end
        end
        return language
    end

end


do -- Define Parser wrapper operators
    -- Choice
    function ParserMT:__add(other)
        return P.choice(self, other)
    end
    -- Sequence
    function ParserMT:__concat(other)
        return P.sequence(self, other)
    end
    -- Right (5.1 compatible)
    function ParserMT:__div(other)
        return self:right(other)
    end
    -- Left (5.1 compatible)
    function ParserMT:__mul(other)
        return self:left(other)
    end
    -- Optional
    function ParserMT:__unm(other)
        return P.optional(other)
    end
    ParserMT.__shr = ParserMT.__div
    ParserMT.__shl = ParserMT.__mul
end
return P
