-module(benchmark_close).
-compile(export_all).

-define(TIMEOUT,100).

main([RemoteHost,Page,Procs,Gets]) -> forker(atom_to_list(RemoteHost),atom_to_list(Page),list_to_integer(atom_to_list(Procs)),list_to_integer(atom_to_list(Gets))),
	register(logproc,spawn(fun logger/0)).

forker(_RemoteHost, _Page, 0, _Gets) -> done;
forker(RemoteHost,Page, ToDo,Gets) -> spawn(benchmark_close,get_loop,[RemoteHost,Page,Gets]),
	forker(RemoteHost,Page,ToDo-1,Gets).

get_loop(_,_,0) -> done;
get_loop(RemoteHost,Page,Gets) ->
	logproc ! {logit,"Getting..."},
	{ok,Socket} = gen_tcp:connect(RemoteHost,80,[binary,{packet,0}]),
	gen_tcp:send(Socket,["GET ",Page," HTTP/1.0\r\nUser-agent: Erlang_benchmark/0.1\r\n\r\n"]),
	recv_loop(),
	gen_tcp:close(Socket),
	get_loop(RemoteHost,Page,Gets-1).

recv_loop() ->
	receive
		{tcp_closed,_} -> {ok,closed};
		{tcp,_Socket,_Data} -> recv_loop();
		_ -> recv_loop()
	after ?TIMEOUT -> {ok,closed} %% If we haven't received an answer packet after 1000 millisecs, we assume that we have the full page
	end.

logger() ->
	receive
		{logit,Mesg} -> io:format("~s~n",[Mesg]), logger();
		_ -> logger()
	end.