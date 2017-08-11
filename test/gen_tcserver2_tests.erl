%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Community of Eltex
%%% @copyright (C) 2017, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(gen_tcserver2_tests).

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

-record(state, {owner :: pid()}).

start(Args) ->
    gen_tcserver:start({local, ?MODULE}, ?MODULE, Args, [non_blocking]).

init([OwnerPid]) when is_pid(OwnerPid) ->
    TC = timer_container:init([], [non_blocking]),
    TC1 = timer_container:cont_start_timer(tc1, timer1, 24 * 60 * 60 * 1000 - 312412, [], TC),
    TC2 = timer_container:cont_start_timer(tc2, timer2, 100, [], TC1),
    TC3 = timer_container:cont_start_timer(tc3, timer3, 24 * 60 * 60 * 1000 - 23, [], TC2),
    {ok, #state{owner = OwnerPid}, {timer_container, TC3}}.

handle_call(_Request, _From, TC, State) ->
    {reply, ok, TC, State}.

handle_cast({start_timer, {TID, Timeout}}, TC, State) ->
    TC1 = timer_container:start_timer(TID, Timeout, [], TC),
    {noreply, TC1, State};

handle_cast(_Msg, TC, State) ->
    {noreply, TC, State}.

handle_info(_Info, TC, State) ->
    {noreply, TC, State}.

handle_timeout(_TCID, TID, _Args, _TTime, TC, #state{owner = Owner} = State) ->
    Owner ! {timeout, TID},
    TC1 = timer_container:timer_ack(TC),
    {noreply, TC1, State};

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
    Timeout = 100,
    {ok, ServerPid} = start([self()]),
    receive_timer(timer2, 5 * Timeout),
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
