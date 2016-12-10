---
title: Line Editor in Go
author: Ichiban
keywords:
  - CLI
  - SSH
  - Golang
date: 2016-12-10
---

[日本語版はこちら](http://qiita.com/ichiban@github/items/1546d2df8842f9737bf5)

# Introduction

It's easy to write an SSH server in Go. In most cases, your SSH server deals with command line inputs from users. Then, you'll need a piece of software called a line editor which converts key strokes into string. In Go, it's `golang.org/x/crypto/ssh/terminal`.

# Write an SSH Server

Let's write an SSH server. You'll need `golang.org/x/crypto/ssh` to write an SSH server in Go.

For example, we'll consider a simple case which echoes back your input lines. It's around 120 lines so you don't look into details. Here's a summary of it:

- Shows prompt by `w.WriteString(prompt)`
- Takes an input line by `l, _, err := r.ReadLine()`
- Echoes back the input line `w.WriteString("\r\nYou've typed: " + string(l) + "\n")`

```go
package main

import (
	"bufio"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os/exec"

	"golang.org/x/crypto/ssh"
)

func main() {
	key, err := privateKey()
	if err != nil {
		log.Fatalf("failed to load private key: %v", err)
	}

	config := &ssh.ServerConfig{NoClientAuth: true}
	config.AddHostKey(key)

	listener, err := net.Listen("tcp", "0.0.0.0:2022")
	if err != nil {
		log.Fatalf("failed to listen on 2022: %v", err)
	}

	for {
		tcp, err := listener.Accept()
		if err != nil {
			log.Printf("failed to accept tcp connection: %v", err)
			continue
		}

		_, chans, reqs, err := ssh.NewServerConn(tcp, config)
		if err != nil {
			log.Printf("failed to handshake: %v", err)
			continue
		}

		go ssh.DiscardRequests(reqs)
		go handleChannels(chans)
	}
}

func handleChannels(chans <-chan ssh.NewChannel) {
	for c := range chans {
		go handleChannel(c)
	}
}

func handleChannel(c ssh.NewChannel) {
	if t := c.ChannelType(); t != "session" {
		msg := fmt.Sprintf("unknown channel type: %s", t)
		c.Reject(ssh.UnknownChannelType, msg)
		return
	}

	conn, _, err := c.Accept()
	if err != nil {
		log.Printf("failed to accept channel: %v", err)
		return
	}
	defer conn.Close()

	r := bufio.NewReader(conn)
	w := bufio.NewWriter(conn)
	prompt := "> "

	for {
		if _, err := w.WriteString(prompt); err != nil {
			log.Printf("failed to write: %v", err)
			return
		}

		if err := w.Flush(); err != nil {
			log.Printf("failed to flush: %v", err)
			return
		}

		l, _, err := r.ReadLine()
		if err != nil {
			log.Printf("failed to read: %v", err)
			return
		}

		if _, err := w.WriteString("\r\nYou've typed: " + string(l) + "\n"); err != nil {
			log.Printf("failed to write: %v", err)
			return
		}

		if err := w.Flush(); err != nil {
			log.Printf("failed to flush: %v", err)
			return
		}
	}
}

func privateKey() (ssh.Signer, error) {
	b, err := privateKeyBytes()
	if err != nil {
		return nil, err
	}

	return ssh.ParsePrivateKey(b)
}

func privateKeyBytes() ([]byte, error) {
	if key, err := ioutil.ReadFile("example.rsa"); err == nil {
		return key, err
	}

	if err := exec.Command("ssh-keygen", "-f", "example.rsa", "-t", "rsa", "-N", "").Run(); err != nil {
		return nil, err
	}

	return ioutil.ReadFile("example.rsa")
}
```

Now try this SSH server. `go run [file name]` will start the server and open a new terminal, type `ssh -p2022 localhost` to open a client. You'll find it's mulfunctioning very early:

- It doesn't show editing states
- `Ctrl-d` won't terminate the session
- Return key doesn't work

In other words, it's not working at all. These problems are because we're not using a line editor.

# Add a line editor to the SSH server

A line editor is a kind of libraries which displays editing states while user is typing and once user hits return key, sends back the confirmed input line to the host program. There're well-known C implementations such as readline, libedit, and linenoise.

The SSH server above doesn't display editing states because it doesn't refresh the displayed contents while user's typing. `Ctrl-d` doesn't work because it's not capable of recognize it yet. Also, It is a return (CR `0x0D`) what it recieves instead of an end of line (LF `0x0A` or CR+LF `0x0D, 0x0A` depending on the platform). Thus, `r.ReadLine()` can't detect confirmation of input lines. In other words, it is key strokes what the SSH server is receiving, not strings. A line editor can retrieve strings out of key strokes.

Now let's add a line editor to the SSH server. It's time for `golang.org/x/crypto/ssh/terminal`. The example code below is around 100 lines so you can skip. The points are:

- Instanciates a line editor `t := terminal.NewTerminal(conn, "> ")`
- Receives a user input line `l, err := t.ReadLine()`
- Echoes back the line `t.Write([]byte("You've typed: " + string(l) + "\r\n"))`

It displays the prompt automatically so we don't have to care.

```go
package main

import (
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"os/exec"

	"golang.org/x/crypto/ssh"
	"golang.org/x/crypto/ssh/terminal"
)

func main() {
	key, err := privateKey()
	if err != nil {
		log.Fatalf("failed to load private key: %v", err)
	}

	config := &ssh.ServerConfig{NoClientAuth: true}
	config.AddHostKey(key)

	listener, err := net.Listen("tcp", "0.0.0.0:2022")
	if err != nil {
		log.Fatalf("failed to listen on 2022: %v", err)
	}

	for {
		tcp, err := listener.Accept()
		if err != nil {
			log.Printf("failed to accept tcp connection: %v", err)
			continue
		}

		_, chans, reqs, err := ssh.NewServerConn(tcp, config)
		if err != nil {
			log.Printf("failed to handshake: %v", err)
			continue
		}

		go ssh.DiscardRequests(reqs)
		go handleChannels(chans)
	}
}

func handleChannels(chans <-chan ssh.NewChannel) {
	for c := range chans {
		go handleChannel(c)
	}
}

func handleChannel(c ssh.NewChannel) {
	if t := c.ChannelType(); t != "session" {
		msg := fmt.Sprintf("unknown channel type: %s", t)
		c.Reject(ssh.UnknownChannelType, msg)
		return
	}

	conn, _, err := c.Accept()
	if err != nil {
		log.Printf("failed to accept channel: %v", err)
		return
	}
	defer conn.Close()

	t := terminal.NewTerminal(conn, "> ")

	for {
		l, err := t.ReadLine()
		if err != nil {
			log.Printf("failed to read: %v", err)
			return
		}

		if _, err := t.Write([]byte("You've typed: " + string(l) + "\r\n")); err != nil {
			log.Printf("failed to write: %v", err)
			return
		}
	}
}

func privateKey() (ssh.Signer, error) {
	b, err := privateKeyBytes()
	if err != nil {
		return nil, err
	}

	return ssh.ParsePrivateKey(b)
}

func privateKeyBytes() ([]byte, error) {
	if key, err := ioutil.ReadFile("example.rsa"); err == nil {
		return key, err
	}

	if err := exec.Command("ssh-keygen", "-f", "example.rsa", "-t", "rsa", "-N", "").Run(); err != nil {
		return nil, err
	}

	return ioutil.ReadFile("example.rsa")
}
```

By installing a line editor, now we can see editing states as we type, terminate the session with `Ctrl-d`, and retrieve input lines.

# Success!

![balloon.png](images/balloon.png)

["Gopher Stickers"](https://github.com/tenntenn/gopher-stickers) by [Takuya Ueda](https://twitter.com/tenntenn) is licensed under [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/deed.ja)

# Conclusion

I explained you can easily add a line editor to your SSH server with `golang.org/x/crypto/ssh/terminal`.

This article was originally written for the first day of [Go (その2) Advent Calendar 2016](http://qiita.com/advent-calendar/2016/go2) in Japanese. When I booked the date, I announced it'll be about some caveat on starting Go.

I wrote this article because I mistakenly made [my own version of line editor](https://github.com/ichiban/linesqueak) without knowing there's a de facto implementation.

So, here's a caveat: the awesome library you came up with oftentimes has a better alternative under `golang.org/x/`.
