-module(benchmark_close).
-compile(export_all).

-define(WAITBETWEENSPAWN,30).

main([RemoteHost,Page,Procs,Gets]) ->
	register(logproc,spawn(fun logger/0)),
	register(stopper,spawn(?MODULE,stopper,[list_to_integer(atom_to_list(Procs))])),
	forker(atom_to_list(RemoteHost),atom_to_list(Page),list_to_integer(atom_to_list(Procs)),list_to_integer(atom_to_list(Gets))).

forker(_RemoteHost, _Page, 0, _Gets) -> done;
forker(RemoteHost,Page, ToDo,Gets) ->
	GetPid = spawn(benchmark_close,get_loop,[RemoteHost,Page,Gets]),
	stopper ! {newproc,GetPid},
	sleep(?WAITBETWEENSPAWN),
	forker(RemoteHost,Page,ToDo-1,Gets).

get_loop(_,_,0) -> done;
get_loop(RemoteHost,Page,Gets) ->
	logproc ! {logit,"Getting..."},
	{ok,Socket} = gen_tcp:connect(RemoteHost,80,[binary,{packet,0}]),
	gen_tcp:send(Socket,["GET ",Page," HTTP/1.0\r\nUser-agent: Erlang_benchmark/0.1\r\n\r\n"]),
	recv_loop(),
	gen_tcp:close(Socket),
	get_loop(RemoteHost,Page,Gets-1).

stopper(0) ->
	io:format("Terminating http-benchmark...~n"),
	init:stop();
stopper(N) ->
	process_flag(trap_exit,true),
	receive
		{newproc,Pid} ->
			io:format("Registered process ~p~n",[Pid]),
			link(Pid),
			stopper(N);
		{'EXIT',Pid,normal} ->
			io:format("Process ~p exited normally~n",[Pid]),
			stopper(N-1)
	end.


recv_loop() ->
	receive
		{tcp_closed,_} -> {ok,closed};
		{tcp,_Socket,_Data} -> recv_loop();
		_ -> recv_loop()
	end.

logger() -> logger(1).

logger(N) ->
	receive
		{logit,Mesg} -> io:format("~p :: ~s~n",[N,Mesg]), logger(N+1);
		_ -> logger(N)
	end.

sleep(Time) ->
	receive
		after Time -> ok
	end.
