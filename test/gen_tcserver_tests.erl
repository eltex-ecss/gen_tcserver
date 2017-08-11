%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Community of Eltex
%%% @copyright (C) 2017, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(gen_tcserver_tests).

-include_lib("eunit/include/eunit.hrl").

-behaviour(gen_tcserver).

%% API
-export([start/1]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/4,
    handle_cast/3,
    handle_info/3,
    handle_timeout/6,
    terminate/2,
    code_change/4
]).

-record(state, {owner :: pid(), stop_repeat = false}).

start(Args) ->
    gen_tcserver:start({local, ?MODULE}, ?MODULE, Args, []).

init([OwnerPid]) when is_pid(OwnerPid) ->
    TC = timer_container:init([]),
    {ok, #state{owner = OwnerPid}, {timer_container, TC}}.

handle_call(_Request, _From, TC, State) ->
    {reply, ok, TC, State}.

handle_cast({start_timer, {TID, Timeout}}, TC, State) ->
    TC1 = timer_container:start_timer(TID, Timeout, [], TC),
    {noreply, TC1, State};

handle_cast(repeat_msg, TC, #state{stop_repeat = false} = State) ->
    gen_server:cast(self(), repeat_msg),
    timer:sleep(20),
    {noreply, TC, State};

handle_cast(_Msg, TC, State) ->
    {noreply, TC, State}.

handle_info(_Info, TC, State) ->
    {noreply, TC, State}.

handle_timeout(_TCID, TID, _Args, _TTime, TC, #state{owner = Owner} = State) ->
    Owner ! {timeout, TID},
    TC1 = timer_container:timer_ack(TC),
    {noreply, TC1, State#state{stop_repeat = true}};

handle_timeout(_TCID, _TID, _Args, _TTime, TC, State) ->
    TC1 = timer_container:timer_ack(TC),
    {noreply, TC1, State}.

terminate(_Reason, #state{} = _State) ->
    ok.

code_change(_OldVsn, TC, State, _Extra) ->
    {ok, TC, State}.

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
timer_1_test() ->
    TimerID = tid,
    Timeout = 100,
    {ok, ServerPid} = start([self()]),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, repeat_msg)),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {TimerID, Timeout}})),
    receive_timer(TimerID, 5 * Timeout),
    erlang:exit(ServerPid, kill).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
timer_2_test() ->
    TimerID = tid,
    Timeout = 100,
    {ok, ServerPid} = start([self()]),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 1}, 1 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 2}, 2 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 3}, 3 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 4}, 4 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 5}, 5 * Timeout}})),
    receive_timer({TimerID, 1}, 2 * Timeout),
    receive_timer({TimerID, 2}, 2 * Timeout),
    receive_timer({TimerID, 3}, 2 * Timeout),
    receive_timer({TimerID, 4}, 2 * Timeout),
    receive_timer({TimerID, 5}, 2 * Timeout),
    erlang:exit(ServerPid, kill).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
timer_3_test() ->
    TimerID = tid,
    Timeout = 100,
    {ok, ServerPid} = start([self()]),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 1}, 5 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 2}, 4 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 3}, 3 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 4}, 2 * Timeout}})),
    ?assertEqual(ok, gen_tcserver:cast(ServerPid, {start_timer, {{TimerID, 5}, 1 * Timeout}})),
    receive_timer({TimerID, 5}, 2 * Timeout),
    receive_timer({TimerID, 4}, 2 * Timeout),
    receive_timer({TimerID, 3}, 2 * Timeout),
    receive_timer({TimerID, 2}, 2 * Timeout),
    receive_timer({TimerID, 1}, 2 * Timeout),
    erlang:exit(ServerPid, kill).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
receive_timer(TimerID, WaitTimeout) ->
    receive
        {timeout, TimerID} ->
            ok
    after
        WaitTimeout ->
            ?assertEqual(timeout_missing, ok)
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
