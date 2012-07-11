-module(benchmark_keepalive).
-compile(export_all).

-define(WAITBETWEENSPAWN,75). %% How many milliseconds do we wait between spawning to GETter processes

main([RemoteHost,Page,Procs,Gets]) ->
	register(logproc,spawn(fun logger/0)),
	register(stopper,spawn(?MODULE,stopper,[-1])),
	forker(atom_to_list(RemoteHost),atom_to_list(Page),list_to_integer(atom_to_list(Procs)),list_to_integer(atom_to_list(Gets))).


forker(_RemoteHost, _Page, 0, _Gets) -> done; %% fork enough processes
forker(RemoteHost,Page, ToDo,Gets) ->
	spawn(?MODULE,benchmark_process,[RemoteHost,Page,Gets]),
	forker(RemoteHost,Page,ToDo-1,Gets),
	sleep(?WAITBETWEENSPAWN).

benchmark_process(RemoteHost,Page,Gets) -> %% open a socket, spawn a child which sends the requests and receive the answers
	{ok,Socket} = gen_tcp:connect(RemoteHost,80,[binary,{packet,0}]),
	Getproc = spawn(?MODULE,get_loop,[Socket,RemoteHost,Page,Gets]),
	stopper ! {newproc,Getproc},
	recv_loop(Getproc).

get_loop(Socket,_RemoteHost,_Page,0) -> gen_tcp:close(Socket); %% Send the requests
get_loop(Socket,RemoteHost,Page,Gets) ->
	logproc ! {logit,self(),"Sending GET"},
	gen_tcp:send(Socket,["GET ",Page," HTTP/1.1\r\nHost: ",RemoteHost,"\r\nUser-agent: Erlang_benchmark/0.1\r\n\r\n"]),
	receive %% from the receiver loop recv_loop, which is in the controlling process of the socket
		{ok,nextget} -> get_loop(Socket,RemoteHost,Page,Gets-1); %% Full answer received, start new request
		{ok,closed} -> logproc ! {logit,self(),"Remote host closed connection"},
			closed
	end.

recv_loop(Getproc) -> %% Receive the requests and notify the getter process
	{ok,EndofanswerPat} = re:compile("</html>"),
	receive
		{tcp_closed,_} -> Getproc ! {ok,closed};
		{tcp,_Socket,Data} ->
			case re:run(Data,EndofanswerPat) of
				{match,_} -> Getproc ! {ok,nextget}, recv_loop(Getproc);
				nomatch -> recv_loop(Getproc);
				_ -> recv_loop(Getproc)
			end;
		_ -> recv_loop(Getproc)
	end.

stopper(0) ->
	io:format("Terminating http-benchmark...~n"),
	init:stop();

stopper(OrigN) ->
	process_flag(trap_exit,true),
	if
		OrigN =:= -1 -> N = 0;
		OrigN /= -1  -> N = OrigN
	end,
	receive
		{'EXIT',From,Reason} ->
			case Reason of
				normal -> logproc ! {logit,From,"Exited normally."};
				_Other  -> logproc ! {errexit,From,Reason,"Exited with non-normal reason: "}
			end,
			stopper(N-1);
		{newproc,Pid} ->
			logproc ! {logit,Pid,"Registered new getter process"},
			link(Pid),
			stopper(N+1)
	end.

logger() -> logger(1).

logger(Num) ->
	receive
		{logit,From,Mesg} -> io:format("~p :: ~p :: ~s~n",[Num, From, Mesg]), logger(Num+1);
		{errexit,From,Reason,Text} -> io:format("~p :: ~p ~s ~p~n",[Num,From,Text,Reason]), logger(Num+1);
		_ -> logger(Num)
	end.

sleep(Time) ->
	receive
	after Time -> ok
	end.
