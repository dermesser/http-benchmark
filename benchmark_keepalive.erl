-module(benchmark_keepalive).
-compile(export_all).

-define(TIMEOUT,200). %% How many milliseconds do we wait before we assume that the answer is complete

main([RemoteHost,Page,Procs,Gets]) -> forker(atom_to_list(RemoteHost),atom_to_list(Page),list_to_integer(atom_to_list(Procs)),list_to_integer(atom_to_list(Gets))),
	register(logproc,spawn(fun logger/0)).

forker(_RemoteHost, _Page, 0, _Gets) -> done; %% fork enough processes
forker(RemoteHost,Page, ToDo,Gets) -> spawn(benchmark_keepalive,benchmark_process,[RemoteHost,Page,Gets]),
	forker(RemoteHost,Page,ToDo-1,Gets).

benchmark_process(RemoteHost,Page,Gets) -> %% open a socket, spawn a child which sends the requests and receive the answers
	{ok,Socket} = gen_tcp:connect(RemoteHost,80,[binary,{packet,0}]),
	Getproc = spawn(benchmark_keepalive,get_loop,[Socket,RemoteHost,Page,Gets]),
	recv_loop(Getproc).

get_loop(Socket,_RemoteHost,_Page,0) -> gen_tcp:close(Socket); %% Send the requests
get_loop(Socket,RemoteHost,Page,Gets) ->
	logproc ! {logit,"Sending GET"},
	gen_tcp:send(Socket,["GET ",Page," HTTP/1.1\r\nHost: ",RemoteHost,"\r\nUser-agent: Erlang_benchmark/0.1\r\n\r\n"]),
	receive %% from the receiver loop recv_loop, which is in the controlling process of the socket
		{ok,nextget} -> get_loop(Socket,RemoteHost,Page,Gets-1); %% Full answer received, start new request
		{ok,closed} -> closed
	end.

recv_loop(Getproc) -> %% Receive the requests and notify the getter process
	receive
		{tcp_closed,_} -> Getproc ! {ok,closed};
		{tcp,_Socket,_Data} -> recv_loop(Getproc);
		_ -> recv_loop(Getproc)
	after ?TIMEOUT -> Getproc ! {ok,nextget}, recv_loop(Getproc) %% If we haven't received an answer packet after 200 millisecs, we assume that we have the full page
	end.

logger() ->
	receive
		{logit,Mesg} -> io:format("~s~n",[Mesg]), logger();
		_ -> logger()
	end.