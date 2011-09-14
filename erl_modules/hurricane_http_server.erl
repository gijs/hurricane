%%% This is the module that exposes an HTTP interface to Hurricane.
%%% Every message that is received will be sent to the http_handler
%%% group of processes to handle. As such, Hurricane is quite
%%% suitable for use as a generic web application server.

-module(hurricane_http_server).

-export([start/1]).

%% Sets up an infinite loop for the managing process so that it never
%% has to exit (and thus be restarted by the supervisor).
loop() ->
    receive
        _ -> ok
    end,
    loop().

%% Starts Mochiweb listening on the port specified in the config (80 is
%% the default). Defines what function Mochiweb should call back to.
%% Enters the service loop.
start(Options) ->
    application:start(mochiweb),
    ListenPort = proplists:get_value(listen_port, Options, 80),
    HandlerGroup = proplists:get_value(handler_group, Options, http_handler),
    ResponseTimeout = proplists:get_value(response_timeout, Options, 10000),

    HttpHandler = fun(Request) ->
        HandlerPid = hurricane_utils:get_best_pid(HandlerGroup),
        SendData = [
            {scheme, Request:get(scheme)},
            {version, Request:get(version)},
            {method, Request:get(method)},
            {headers, mochiweb_headers:to_list(Request:get(headers))},
            {raw_path, Request:get(raw_path)},
            {path, Request:get(path)},
            {params, Request:parse_qs()},
            {body, Request:recv_body(Request:get(body_length))}
        ],
        HandlerPid ! {request, erlang:self(), http_request, SendData},
        receive
            {response, _FromPid, http_request, Data} -> Request:respond(Data)
        after ResponseTimeout ->
            Request:respond({504, [], "Internal Timeout."})
        end
    end,

    mochiweb_http:start(
        [
            {name, proplists:get_value(name, Options, default)},
            {loop, HttpHandler},
            {port, ListenPort}
        ]
    ),
    loop().
