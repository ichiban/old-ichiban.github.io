---
title: How to parse string-or-number JSON in Golang
author: Ichiban
date: 2016-10-30
keywords:
  - Web
  - JSON
  - Golang
---

In this post, I'm going to explain how to parse JSON data with a field which can be either a string or number in Go.

Go has a great support for JSON. In many cases what you have to do is to define corresponding `struct`s to parse JSON.

Let's say we're dealing with a Web API provided by some other company. It gives us a series of name-value pairs in this format:

```json
[
  {
    "name" : "foo",
    "value" : 100
  },
  {
    "name" : "bar",
    "value" : 100
  }
]
```

We can assume `name` is a string and `value` is a number. Thus, the corresponding `struct` will be like this:

```go
type NameValue struct{
	Name  string
	Value float64
}
```

Now we can parse the JSON like this:

```go
package main

import (
	"encoding/json"
	"fmt"
)

func main() {
	data := `[
		{
			"name" : "foo",
			"value" : 100
		},
		{
			"name" : "bar",
			"value" : 200
		}
	]`

	var nvs []NameValue
	if err := json.Unmarshal([]byte(data), &nvs); err != nil {
		panic(err)
	}

	for i := 0; i < len(nvs); i++ {
		fmt.Printf("result[%d]: %+v\n", i, nvs[i])
	}
}

type NameValue struct{
	Name  string
	Value float64
}
```

```
result[0]: {Name:foo Value:100}
result[1]: {Name:bar Value:200}
```

Cool. Then suddenly you realize that `value` isn't always a number- it can be a string:

```json
[
  {
    "name" : "foo",
    "value" : 100
  },
  {
    "name" : "bar",
    "value" : 200
  },
  {
    "name" : "baz",
    "value" : "X300"
  }
]
```

```

panic: json: cannot unmarshal string into Go value of type float64

goroutine 1 [running]:
panic(0x124740, 0x10532340)
	/usr/local/go/src/runtime/panic.go:500 +0x720
main.main()
	/tmp/sandbox440216281/main.go:27 +0x140
```

Now it's messed up. But no worries. We can handle this situation by making `Value` either string or number instead of just string:

```json
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
)

func main() {
	data := `[
		{
			"name" : "foo",
			"value" : 100
		},
		{
			"name" : "bar",
			"value" : 200
		},
		{
			"name" : "baz",
			"value" : "X300"
		}
	]`

	var nvs []NameValue
	if err := json.Unmarshal([]byte(data), &nvs); err != nil {
		panic(err)
	}

	for i := 0; i < len(nvs); i++ {
		fmt.Printf("result[%d]: %+v\n", i, nvs[i])
	}
}

type NameValue struct{
	Name  string
	Value StringOrNumber
}

type StringOrNumber struct{
	String string
}

func (s *StringOrNumber) UnmarshalJSON(data []byte) error {
	dec := json.NewDecoder(bytes.NewReader(data))
	
	var v interface{}
	if err := dec.Decode(&v); err != nil {
		return err
	}
	
	switch v.(type) {
	case string:
		s.String = v.(string)
	case float64:
		s.String = fmt.Sprintf("%d", int(v.(float64)))
	default:
		return fmt.Errorf("unknown type: %+v", v)
	}
	
	return nil
}
```

```
result[0]: {Name:foo Value:{String:100}}
result[1]: {Name:bar Value:{String:200}}
result[2]: {Name:baz Value:{String:X300}}
```

Now we can handle a string-or-number JSON field.

This is based on my real life experience and now I'm seeing a case where `Value` can also be an object which I don't know how to handle gracefully. Life is tough.
