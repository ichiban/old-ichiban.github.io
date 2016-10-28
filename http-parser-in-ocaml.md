---
title: HTTP/1.1 parser in OCaml
author: Ichiban
keywords:
  - Web
  - HTTP
  - State Machine
  - OCaml
date: 2016-10-23
---

A function and algebraic data type can make a full-fledged HTTP/1.1 Parser. I was bored on high-level web stuff and digged into one of the very basic of web technologies -- HTTP parser. I looked into Node.js's [HTTP Parser](https://github.com/nodejs/http-parser) which is based on NGINX's parser. It's written in C and [I reconstructed it in OCaml](https://github.com/ichiban/1w). I'm going to explain what it does in a simplified HTTP method parser example which is a subset of the full HTTP/1.1 parser.

HTTP parser is not in Yacc/Lex. When it comes to parsing structured text data, you may pick Yacc and Lex for the tools, or parser combinators maybe. Though, you can't make use of those tools because an HTTP parser is allowed to see only a tiny fraction of data at a time. HTTP is based on TCP and data in TCP are transfered in several TCP packets.

HTTP Parser is a State Machine. It consumes one ASCII character at a time and changes its internal state. It also triggers callbacks when interesting events happen. In this way, it can phase parsing -- process as many bytes as possible and wait until the next chunk arrives.

A State Machine is a function. It takes an old state and a character then returns a new state. When we get another charater, use the new state as an old state, pass them to the function again, and repeat this iteration until it reaches a terminal state.

```ocaml
val f : state -> char -> state
```

A state is an algebraic data type. It needs to keep track of parsing and remember a couple of things:

- Which syntactic element we're at now
- In this syntactic element, how many characters we're in
- In this syntactic element, how many characters we're going to have
- Etc.

We can use a Variant to represent them. For example, If we're at the very beginning of HTTP method, it's `MethodStart`. If we're at the 3rd character of HTTP method, it's `Method (3, m)` where `m` is the index of the first character of method. Well, I'll explain the `m` part later.

```ocaml
type state =
  | MethodStart
  | Method of int * int
  | SpacesBeforeUri
```

Callbacks make things a little bit complicated, though. Here's a partial HTTP parser example that parses HTTP method:

```ocaml
exception InvalidMethod

let parse_method on_method data state p =
  let ch = String.get data p in
  match state, ch with
  | MethodStart, ch when 'A' <= ch && ch <= 'Z' ->
     Method (1, p)
  | MethodStart, _ -> (* invalid token *)
     raise InvalidMethod
  | Method (n, m), _ when n > 255 -> (* too long *)
     raise InvalidMethod
  | Method (n, m), ' ' ->
     on_method data m p;
     SpacesBeforeUri
  | Method (n, m), ch when 'A' <= ch && ch <= 'Z' ->
     Method (n + 1, m)
  | Method _, _ -> (* invalid token *)
     raise InvalidMethod
```

This will parse "GET", "PUT", "POST", "DELETE" or any other HTTP method-ish strings followed by a space.

As you can see, it's not `state -> char -> state`. Its type is actually a bit more complicated.

```ocaml
type callback = string -> int -> int -> unit
val parse_method : callback -> string -> state -> int -> state
```

First `callback` is `on_method` callback function. When the state machine finds (a part of) HTTP method, it triggers the callback so that we can extract a substring of `data`. Next `string` is `data` currently available for parsing. Last `state -> int -> state` is a slight modification of `state -> char -> state`. Since we want to get HTTP method when we reach the end of method, we need to keep track of index of the first character of the syntactic element (in this case, HTTP method). That's the `m` part.

Also, since we can see only a tiny fraction of `data` at a time, we need to refill `data` after we consume all of it. In that case, we need to reset `m` which points to a character in the previous `data` since `m` doesn't mean anything in the new `data`. Before we reset `m` to 0, we need to trigger the callback for a substring of `data` from `m` to the end of `data`. So, we may have several `on_message` callbacks for a single HTTP method.

By following this approach, a full-fledged HTTP/1.1 parser can be constructed. [My implementation is on GitHub](https://github.com/ichiban/1w).
