
compile:
	mix compile

cleanlogs:
	rm logs/*.LOG

test: compile cleanlogs
	mix test

dev1-console:
	MINIDOTE_NODES='minidote1@127.0.0.1,minidote2@127.0.0.1,minidote3@127.0.0.1' iex --name minidote1@127.0.0.1 -S mix

dev2-console:
	MINIDOTE_NODES='minidote1@127.0.0.1,minidote2@127.0.0.1,minidote3@127.0.0.1' iex --name minidote2@127.0.0.1 -S mix

dev3-console:
	MINIDOTE_NODES='minidote1@127.0.0.1,minidote2@127.0.0.1,minidote3@127.0.0.1' iex --name minidote3@127.0.0.1 -S mix
