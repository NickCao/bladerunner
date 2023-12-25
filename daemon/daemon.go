package main

import (
	"crypto/ed25519"
	"crypto/rand"
	"flag"
	"log"
	"log/slog"
	"net"
	"os"
	"os/exec"

	"golang.org/x/crypto/ssh"
)

var addr = flag.String("l", "127.0.0.1:2022", "address to listen on")

func main() {
	flag.Parse()

	_, key, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		log.Fatal(err)
	}

	signer, err := ssh.NewSignerFromKey(key)
	if err != nil {
		log.Fatal(err)
	}

	var config = &ssh.ServerConfig{
		NoClientAuth: true,
	}

	config.AddHostKey(signer)

	listener, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println(err)
			continue
		}
		go conn_handler(conn, config)
	}
}

func conn_handler(conn net.Conn, config *ssh.ServerConfig) {
	slog.Info("new conn", "remote", conn.RemoteAddr().String())

	server, channel, requests, err := ssh.NewServerConn(conn, config)
	if err != nil {
		slog.Error("new server conn error", "error", err)
		return
	}
	defer server.Close()

	go ssh.DiscardRequests(requests)

	for chr := range channel {
		go chan_handler(chr)
	}
}

func chan_handler(chr ssh.NewChannel) {
	slog.Info("new chan", "type", chr.ChannelType())

	if chr.ChannelType() != "session" {
		err := chr.Reject(ssh.UnknownChannelType, "unknown channel type")
		slog.Error("new chan rejected", "error", err)
		return
	}

	channel, requests, err := chr.Accept()
	if err != nil {
		slog.Error("new chan error", "error", err)
		return
	}

	for request := range requests {
		if request.Type != "exec" {
			if request.WantReply {
				request.Reply(false, nil)
			}
			continue
		}

		var command = exec.Command("/bin/nix", "daemon",
			"--stdio", "--extra-experimental-features", "nix-command daemon-trust-override", "--force-trusted")

		command.Stdin = channel
		command.Stdout = channel
		command.Stderr = os.Stderr

		err = command.Start()
		if err != nil {
			slog.Error("daemon error", "error", err)
			if request.WantReply {
				request.Reply(false, nil)
			}
			return
		}

		if request.WantReply {
			request.Reply(true, nil)
		}
	}
}
