# Microparsel
A parser combinator library for Lua inspired by the Haskell library Parsec, designed as a 0 dependency single file compatible with Lua 5.1, 5.2, 5.3, and Roblox Luau. Some of this was adapted from Hasura's lovely blog on the topic available at https://hasura.io/blog/parser-combinators-walkthrough/

While this is intended to be used for parsing, it's also useful for making up for the deficiencies of Lua's pattern matching. Syntactically it's kind of bulky for this use case, but this library is much smaller than, say, an actual Regex implementation.

This project is licensed under LGPL v2.1. This means (roughly) that should you make any modifications to any of the files in this git repo, you should make said changes publicly available, however there is no requirement to make code that uses this module publicly available. If you think a core parser combinator is missing, add it to the library and make it public! If it's something more specific, just throw it in another file and legally you're good to go.

# Contributing
Please make a ticket before making a merge request. This library should remain small, dependency-less, and compatible with Lua 5.1+ and Roblox Luau. All MRs should be linked to a ticket. Tickets take priority in the order of: bugs fixes, making tests, simplification, and finally new features.

# Documentation
See [Wiki](https://github.com/RegularTetragon/microparsel/wiki)
