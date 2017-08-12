%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Community of Eltex
%%% @copyright (C) 2017, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(gen_tcserver).

-behaviour(gen_server).

-export([
    start/3,
    start/4,
    start_link/3,
    start_link/4,
    call/2,
    call/3,
    cast/2,
    reply/2,
    abcast/2,
    abcast/3,
    multi_call/2,
    multi_call/3,
    multi_call/4,
    enter_loop/3,
    enter_loop/4,
    enter_loop/5
]).

-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3,
    format_status/2
]).

-record(timer_state, {
    ref = undefined :: reference() | undefined,
    body :: term()
}).

-record(s, {
    module,
    mstate,
    tcontainer,
    no_hibernate_timeout,
    hibernate_timer_ref = #timer_state{}
}).

%%%===================================================================
%%% Callbacks
%%%===================================================================
-callback init(Args :: term()) ->
    {ok, State :: term()} |
    {ok, State :: term(), timeout() | hibernate | {timer_container, term()}} |
    {stop, Reason :: term()} | ignore.
-callback handle_call(Request :: term(), From :: {pid(), Tag :: term()}, TCState :: term(), State :: term()) ->
    {reply, Reply :: term(), NewTCState :: term(), NewState :: term()} |
    {reply, Reply :: term(), NewTCState :: term(), NewState :: term(), hibernate} |
    {noreply, NewTCState :: term(), NewState :: term()} |
    {noreply, NewTCState :: term(), NewState :: term(), hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewTCState :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewTCState :: term(), NewState :: term()}.
-callback handle_cast(Request :: term(), TCState :: term(), State :: term()) ->
    {noreply, NewTCState :: term(), NewState :: term()} |
    {noreply, NewTCState :: term(), NewState :: term(), hibernate} |
    {stop, Reason :: term(), NewState :: term()} |
    {stop, Reason :: term(), NewTCState :: term(), NewState :: term()}.
-callback handle_info(Info :: timeout() | term(), TCState :: term(), State :: term()) ->
    {noreply, NewTCState :: term(), NewState :: term()} |
    {noreply, NewTCState :: term(), NewState :: term(), hibernate} |
    {stop, Reason :: term(), NewTCState :: term(), NewState :: term()}.
-callback handle_timeout(TCID :: term(), TID :: term(), Arg :: term(), TTime :: term(), TCState :: term(), State :: term()) ->
    {noreply, NewTCState :: term(), NewState :: term()} |
    {noreply, NewTCState :: term(), NewState :: term(), hibernate} |
    {stop, Reason :: term(), NewTCState :: term(), NewState :: term()}.
-callback terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()), State :: term()) ->
    term().
-callback code_change(OldVsn :: (term() | {down, term()}), TCState :: term(), State :: term(), Extra :: term()) ->
    {ok, NewTCState :: term(), NewState :: term()} | {error, Reason :: term()}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%%===================================================================
%%% API
%%%===================================================================
start(Module, Args, Options) ->
    gen_server:start(?MODULE, [Args, Options, Module], Options).

start(Name, Module, Args, Options) ->
    gen_server:start(Name, ?MODULE, [Args, Options, Module], Options).

start_link(Module, Args, Options) ->
    gen_server:start_link(?MODULE, [Args, Options, Module], Options).

start_link(Name, Module, Args, Options) ->
    gen_server:start_link(Name, ?MODULE, [Args, Options, Module], Options).

init([Args, Options, Module]) ->
    TO = proplists:get_value(no_hibernate_timeout, Options, undefined),
    case Module:init(Args) of
        {ok, MState, hibernate} ->
            State = #s{
                module = Module,
                mstate = MState,
                no_hibernate_timeout = TO,
                tcontainer = timer_container:init([], Options)
            },
            {ok, State, hibernate};
        {ok, MState, {timer_container, TC}} ->
            TS = timer_container:init(TC, Options),
            {T, NewTRef} = get_timeout(TO, TS, #timer_state{}),
            State = #s{
                module = Module,
                mstate = MState,
                tcontainer = TS,
                no_hibernate_timeout = TO,
                hibernate_timer_ref = NewTRef
            },
            {ok, State, T};
        {ok, MState} ->
            State = #s{
                module = Module,
                mstate = MState,
                no_hibernate_timeout = TO,
                tcontainer = timer_container:init([], Options)
            },
            {ok, State};
        {ok, _MState, _T} = Return ->
            {stop, {bad_return, Return}};
        R -> R
    end.

call(Name, Req) ->
    gen_server:call(Name, Req).

call(Name, Req, Timeout) ->
    gen_server:call(Name, Req, Timeout).

cast(Dest, Req) ->
    gen_server:cast(Dest, Req).

reply(To, Reply) ->
    gen_server:reply(To, Reply).

abcast(Name, Req) ->
    gen_server:abcast(Name, Req).

abcast(Nodes, Name, Req) ->
    gen_server:abcast(Nodes, Name, Req).

multi_call(Name, Req) ->
    gen_server:multi_call(Name, Req).

multi_call(Nodes, Name, Req) ->
    gen_server:multi_call(Nodes, Name, Req).

multi_call(Nodes, Name, Req, Timeout) ->
    gen_server:multi_call(Nodes, Name, Req, Timeout).

enter_loop(Mod, Options, State) ->
    gen_server:enter_loop(Mod, Options, State).

enter_loop(Mod, Options, State, ServerName) ->
    gen_server:enter_loop(Mod, Options, State, ServerName).

enter_loop(Mod, Options, State, ServerName, Timeout) ->
    gen_server:enter_loop(Mod, Options, State, ServerName, Timeout).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

handle_cast(Msg, State = #s{module = Module, mstate = MState, tcontainer = TS}) ->
    case Module:handle_cast(Msg, TS, MState) of
        {noreply, NTS, NewMState} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {noreply, NTS, NewMState, hibernate} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {stop, Reason, NTS, NewMState} ->
            {stop, Reason, State#s{tcontainer = NTS, mstate = NewMState}};
        {stop, Reason, NewMState} ->
            {stop, Reason, State#s{mstate = NewMState}} %%% ????
    end.

%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

handle_call(Msg, From, State = #s{module = Module, mstate = MState, tcontainer = TS}) ->
    case Module:handle_call(Msg, From, TS, MState) of
        {reply, Reply, NTS, NewMState} ->
            gen_server:reply(From, Reply),
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {reply, Reply, NTS, NewMState, hibernate} ->
            gen_server:reply(From, Reply),
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {noreply, NTS, NewMState} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {noreply, NTS, NewMState, hibernate} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {stop, Reason, Reply, NTS, NewMState} ->
            {stop, Reason, Reply, State#s{mstate = NewMState, tcontainer = NTS}};
        {stop, Reason, NTS, NewMState} ->
            {stop, Reason, State#s{mstate = NewMState, tcontainer = NTS}}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

handle_info(timeout, State = #s{hibernate_timer_ref = #timer_state{body = _TimerMsg}}) ->
    try_handle_timeout_and_return(State);
handle_info(InfoMsg, State = #s{hibernate_timer_ref = #timer_state{body = InfoMsg}}) ->
    try_handle_timeout_and_return(State);

handle_info({timeout, _}, State = #s{}) ->
    try_handle_timeout_and_return(State);

handle_info(Info, State = #s{module = Module, mstate = MState, tcontainer = TS}) ->
    case Module:handle_info(Info, TS, MState) of
        {noreply, NTS, NewMState} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {noreply, NTS, NewMState, hibernate} ->
            try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS});
        {stop, Reason, NTS, NewMState} ->
            {stop, Reason, State#s{mstate = NewMState, tcontainer = NTS}}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

terminate(Reason, _S = #s{module = Module, mstate = MState}) ->
    Module:terminate(Reason, MState),
    ok.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

code_change(OldVsn, State = #s{module = Module, mstate = MState, tcontainer = TS}, Extra) ->
    {ok, NTS, NewMState} = Module:code_change(OldVsn, TS, MState, Extra),
    {ok, State#s{mstate = NewMState, tcontainer = NTS}}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

format_status(Opt, [PDict, #s{module = Module, mstate = MState, tcontainer = TContainer}]) ->
    [{data, [{"gen_module", ?MODULE}, {"callback_module", Module}, {"tcontainer", TContainer}] ++
        case erlang:function_exported(Module, format_status, 2) of
            true ->
                case catch Module:format_status(Opt, [PDict, MState]) of
                    {'EXIT', _Reason} -> [{data, [{"UserState", MState}]}];
                    Result when is_list(Result) -> Result;
                    Result -> [Result]
                end;
            false -> [{data, [{"UserState", MState}]}]
        end}].

%%%===================================================================
%%% Internal functions
%%%===================================================================
get_timeout(TO, TC, #timer_state{ref = TRef}) ->
    erlang:is_reference(TRef) andalso erlang:cancel_timer(TRef),
    case timer_container:get_actual_timeout(TC) of
        infinity when TO =:= undefined ->
            {infinity, #timer_state{}};
        infinity ->
            {hibernate, #timer_state{}};
        T when T < TO ->
            {T, #timer_state{}};
        T ->
            Body = {timeout, erlang:make_ref()},
            Ref = erlang:send_after(T, self(), Body),
            {hibernate, #timer_state{ref = Ref, body = Body}}
    end.

try_handle_timeout_and_return(#s{module = Module, mstate = MState, tcontainer = TS,
        no_hibernate_timeout = TO, hibernate_timer_ref = #timer_state{} = TRef} = State) ->
    case timer_container:process_timeout(TS) of
        {none, NTS} ->
            {T, NewTRef} = get_timeout(TO, NTS, TRef),
            {noreply, State#s{mstate = MState, tcontainer = NTS, hibernate_timer_ref = NewTRef}, T};
        {wait_timeout, _TCID, _TID, _Arg, _TTime, _NTS} ->
            {stop, wait_timeout, State};
        {TCID, TID, Arg, TTime, NTS} ->
            case Module:handle_timeout(TCID, TID, Arg, TTime, NTS, MState) of
                {noreply, NTS1, NewMState, hibernate} ->
                    try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS1});
                {noreply, NTS1, NewMState} ->
                    try_handle_timeout_and_return(State#s{mstate = NewMState, tcontainer = NTS1});
                {stop, Reason, NTS1, NewMState} ->
                    {stop, Reason, State#s{mstate = NewMState, tcontainer = NTS1}}
            end
    end.
