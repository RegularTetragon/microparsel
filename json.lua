-- Proof of concept json parser

local P = require("microparsel")
local language = P.language


local json = language {
    value = function(lang)
        return lang:whitespace() >> P.choice(
            lang:boolean(),
            lang:number(),
            lang:string(),
            lang:null(),
            lang:list(),
            lang:dict()
        ) << lang:whitespace()
    end;
    whitespace = function(lang)
        return P.match("%s*")
    end;
    innerString = function(lang, quoteChar)
        return P.many(
            (P.match('\\') >> P.any)
            +
            (P.match('[^'..quoteChar..']'))
        ):map(table.concat)
    end;
    string = function(lang)
        return (P.match('"') >> lang:innerString('"') << P.match('"')) + (P.match("'") >> lang:innerString("'") << P.match("'"))
    end;
    number = function (lang)
        return P.sequence(
            P.match("%d+"),
            P.optional(P.match("%.%d+"), ""),
            P.optional(P.match("e%d+"), "")
        ):map(table.concat):map(tonumber)
    end;
    null = function (lang)
        return P.match("null"):result(nil)
    end;
    boolean = function(lang)
        return P.match("true"):result(true) + P.match("false"):result(false)
    end;
    list = function(lang)
        return P.match("%[") >> P.sepBy(P.match(","), lang:value()) << P.match("%]")
    end;
    dict = function(lang)
        return P.match("%{") >> P.sepBy(
            P.match(","),
            P.sequence(
                lang:string(),
                P.match(":"),
                lang:value()
            )
        ):map(
            function(kvpairs)
                local result = {}
                for _, kvpair in pairs(kvpairs) do
                    result[kvpair[1]] = kvpair[3]
                end
                return result
            end
        ) << P.match("%}") 
    end
}

return json