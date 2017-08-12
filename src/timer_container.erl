%%%-------------------------------------------------------------------
%%% -*- coding: utf-8 -*-
%%% @author Community of Eltex
%%% @copyright (C) 2017, Eltex, Novosibirsk, Russia
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(timer_container).
-compile(inline).
-compile(inline_list_funcs).
-compile(no_strict_record_tests).

%% CORE API
-export([
    init/1,
    init/2,
    start_timer/4,
    start_timer_local/4,
    start_timer/5,
    start_timer_local/5,
    cont_start_timer/5,
    cont_start_timer_local/5,
    cont_start_timer/6,
    cont_start_timer_local/6,
    cancel_timer/2,
    cont_cancel_timer/3,
    cont_cancel_timers/2,
    timer_ack/1,
    cont_timer_ack/2,
    cont_timer_ack/3
]).

%% EXTEND API
-export([
    is_exist/2,
    cont_is_exist/3,
    filter_cont/2,
    filter_timers/3,
    get_timer_info/2,
    cont_get_timer_info/3,
    process_timeout/1,
    get_actual_timeout/1,
    get_actual_timeout/2,
    get_waiting_timeout/1,
    flush/1,
    reactivate/1,
    is_container/1
]).

%% MIGRATION
-export([
    export/1,
    import/2,
    cont_cleanup/2,
    cont_export/2,
    cont_import/2,
    cont_import/3
]).

%% DEBUG
-export([
    dbg_info/1,
    cont_dbg_info/2,
    all_dbg_info/1
]).

-export_type([timer_container/0, t_container/0]).

-compile({
    inline,
    [
        start_timer/4,
        start_timer_local/4,
        start_timer/5,
        start_timer_local/5,
        cont_start_timer/5,
        cont_start_timer_local/5,
        cont_start_timer/6,
        cont_start_timer_local/6,
        cancel_timer/2,
        timer_ack/1,
        is_exist/2
    ],
    is_container
}).

-type tc_state() :: active | wait.

%%--------------------------------------------------------------------
%% @doc local - такие таймера удаляются из контейнера при вызове flush
%%      global - такие таймера не удаляются из контейнера при вызове flush - сторятся
%%--------------------------------------------------------------------
-type timer_type() :: local | global.

-record(ts_timer, {
    timer_id :: term(),             %% идентификатор таймера, задается пользователем
    timer_time,                     %% время срабатывания таймера
    timer_arg :: term(),            %% аргументы таймера
    timer_type = global :: timer_type()
}).

-define(DEFAULT_CONTAINER_ID, default).
-define(VERY_LONG_TIMER, 16#FFFFFFFF).

-record(t_container, {
    id = ?DEFAULT_CONTAINER_ID :: term(),    %% идентификатор контейнера
    state = active :: tc_state(),            %% логическое состояние
    timers = [] :: [#ts_timer{}],            %% список активных таймеров
    local_timers = 0 :: non_neg_integer(),   %% количество local таймеров в t_container-е
    wait_timeout                             %% время истечения wait таймера
}).

-record(timer_container, {
    non_blocking = false,
    t_containers = [] :: [#t_container{}]
}).

-type t_container() :: #t_container{}.
-type timer_container() :: #timer_container{}.

-define(DEFAULT_WAIT_TIMEOUT, 10000).

-define(NOW, erlang:system_time(millisecond)). % TC работает в миллисекундном диапазоне.

%%%===================================================================
%%% CORE API
%%%===================================================================

-spec init(Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Init timer containers
%%--------------------------------------------------------------------
init(#timer_container{t_containers = []} = Cont) ->
    Cont;
init(#timer_container{t_containers = TCont} = Cont) ->
    TCont1 = [TC#t_container{state = active} || TC <- TCont],
    Cont#timer_container{t_containers = TCont1};
init(_) ->
    #timer_container{t_containers = []}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec init(TC :: timer_container(), Args :: [{Key :: term(), Val :: term()}]) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Init timer containers
%%--------------------------------------------------------------------
init(TC, Args) ->
    Cont = init(TC),
    Cont#timer_container{non_blocking = lists:member(non_blocking, Args)}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec start_timer(
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start global timer in default t_container and current time
%%--------------------------------------------------------------------
start_timer(TID, Duration, Arg, Cont) ->
    cont_start_timer(?NOW, ?DEFAULT_CONTAINER_ID, TID, global, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec start_timer_local(
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start local timer in default t_container and current time
%%--------------------------------------------------------------------
start_timer_local(TID, Duration, Arg, Cont) ->
    cont_start_timer_local(?DEFAULT_CONTAINER_ID, TID, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec start_timer(
    NowTime :: non_neg_integer(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start global timer in default t_container and user time
%%--------------------------------------------------------------------
start_timer(NowTime, TID, Duration, Arg, Cont) ->
    cont_start_timer(NowTime, ?DEFAULT_CONTAINER_ID, TID, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec start_timer_local(
    NowTime :: non_neg_integer(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start local timer in default t_container and user time
%%--------------------------------------------------------------------
start_timer_local(NowTime, TID, Duration, Arg, Cont) ->
    cont_start_timer_local(NowTime, ?DEFAULT_CONTAINER_ID, TID, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_start_timer(
    TCID :: term(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start global timer in specified t_container and current time
%%--------------------------------------------------------------------
cont_start_timer(TCID, TID, Duration, Arg, Cont) ->
    cont_start_timer(?NOW, TCID, TID, global, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_start_timer_local(
    TCID :: term(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start local timer in specified t_container and current time
%%--------------------------------------------------------------------
cont_start_timer_local(TCID, TID, Duration, Arg, Cont) ->
    cont_start_timer(?NOW, TCID, TID, local, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_start_timer(
    NowTime :: non_neg_integer(),
    TCID :: term(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start global timer in specified t_container and user time
%%--------------------------------------------------------------------
cont_start_timer(undefined, TCID, TID, Duration, Arg, Cont) ->
    cont_start_timer(?NOW, TCID, TID, global, Duration, Arg, Cont);
cont_start_timer(NowTime, TCID, TID, Duration, Arg, Cont) ->
    cont_start_timer(NowTime, TCID, TID, global, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_start_timer_local(
    NowTime :: non_neg_integer(),
    TCID :: term(),
    TID :: term(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc start local timer in specified t_container and user time
%%--------------------------------------------------------------------
cont_start_timer_local(NowTime, TCID, TID, Duration, Arg, Cont) ->
    cont_start_timer(NowTime, TCID, TID, local, Duration, Arg, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_start_timer(
    NowTime :: non_neg_integer(),
    TCID :: term(),
    TID :: term(),
    TType :: timer_type(),
    Duration :: non_neg_integer(),
    Args :: [{Key :: term(), Val :: term()}],
    Cont :: timer_container()
) -> timer_container() | no_return().
%%--------------------------------------------------------------------
%% @doc start global or local timer in specified t_container
%%--------------------------------------------------------------------
cont_start_timer({_, _, _} = NowTime, TCID, TID, TType, Duration, Arg, Cont) ->
    cont_start_timer(now_us(NowTime), TCID, TID, TType, Duration, Arg, Cont);
cont_start_timer(NowTime, TCID, TID, TType, Duration, Arg, #timer_container{t_containers = []} = Cont) ->
    NewCont = Cont#timer_container{t_containers = [#t_container{id = TCID}]},
    cont_start_timer(NowTime, TCID, TID, TType, Duration, Arg, NewCont);
cont_start_timer(NowTime, TCID, TID, TType, Duration, Arg, Cont) ->
    TCont = Cont#timer_container.t_containers,
    TC1 =
        case lists:keyfind(TCID, #t_container.id, TCont) of
            #t_container{state = wait, timers = [#ts_timer{timer_id = TID} | _]} = TC ->
                add_timer_tail(NowTime, TID, Duration, Arg, TType, TC);
            #t_container{state = wait, timers = [#ts_timer{timer_time = {HeadTimerTime, _}} | _]} = TC ->
                NewTimerTime =
                    if
                        Duration > ?VERY_LONG_TIMER ->
                            new_now(NowTime, ?VERY_LONG_TIMER);
                        true ->
                            new_now(NowTime, Duration)
                    end,
                if
                    NewTimerTime < HeadTimerTime ->
                        erlang:error({error, {obsolete_timer, {TCID, TID}}});
                    true ->
                        ok
                end,
                add_timer(NowTime, TID, Duration, Arg, TType, TC);
            #t_container{} = TC ->
                add_timer(NowTime, TID, Duration, Arg, TType, TC);
            false ->
                add_timer(NowTime, TID, Duration, Arg, TType, #t_container{id = TCID})
        end,
    Cont#timer_container{t_containers = update_containers(TC1, TCont)}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cancel_timer(TID :: term(), TC :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc cancel timer in default t_container
%%--------------------------------------------------------------------
cancel_timer(TID, TC) ->
    cont_cancel_timer(?DEFAULT_CONTAINER_ID, TID, TC).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_cancel_timer(
    TCID :: term(),
    TID :: term(),
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc cancel timer in specified t_container
%%--------------------------------------------------------------------
cont_cancel_timer(_TCID, _TID, #timer_container{t_containers = []} = Cont) ->
    Cont;
cont_cancel_timer(TCID, TID, #timer_container{t_containers = TCont} = Cont) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{state = wait, timers = [#ts_timer{timer_id = TID} | _]} ->
            cont_timer_ack(TCID, Cont);
        #t_container{state = active, timers = [#ts_timer{timer_id = TID}]} ->
            Cont#timer_container{t_containers = delete_t_container(TCID, TCont)};
        #t_container{} = TC ->
            case delete_timer(TID, TC) of
                not_found ->
                    Cont;
                {ok, TC1} ->
                    Cont#timer_container{
                        t_containers = lists:keystore(TCID, #t_container.id, TCont, TC1)
                    };
                {resort, TC1} ->
                    Cont#timer_container{t_containers = update_containers(TC1, TCont)}
            end;
        false ->
            Cont
    end.

-spec cont_cancel_timers(TCID :: term(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Cancel timers in container id
%%--------------------------------------------------------------------
cont_cancel_timers(_TCID, #timer_container{t_containers = []} = Cont) ->
    Cont;
cont_cancel_timers(TCID, #timer_container{t_containers = TCont} = Cont) ->
    TCont2 = delete_t_container(TCID, TCont),
    Cont#timer_container{t_containers = TCont2}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec timer_ack(Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Timer ack in ANY (closest) container.
%%--------------------------------------------------------------------
timer_ack(#timer_container{t_containers = []} = Cont) ->
    Cont;
timer_ack(#timer_container{t_containers = [#t_container{id = TCID} | _]} = Cont) ->
    cont_timer_ack(TCID, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_timer_ack(TCID :: term(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc timer ack in specified container.
%%--------------------------------------------------------------------
cont_timer_ack(_TCID, #timer_container{t_containers = []} = Cont) ->
    Cont;
cont_timer_ack(TCID, #timer_container{t_containers = TCont} = Cont) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{timers = []} ->
            post_ack_process(Cont, TCont, [], TCID);
        #t_container{state = wait, timers = [#ts_timer{}]} ->
            post_ack_process(Cont, TCont, [], TCID);
        #t_container{state = wait, timers = [#ts_timer{timer_type = local} | T]} = TC ->
            LocalTCount = TC#t_container.local_timers,
            TC1 = TC#t_container{state = active, timers = T, local_timers = LocalTCount - 1},
            post_ack_process(Cont, TCont, TC1, TCID);
        #t_container{state = wait, timers = [_H | T]} = TC ->
            TC1 = TC#t_container{state = active, timers = T},
            post_ack_process(Cont, TCont, TC1, TCID);
        #t_container{state = active} ->
            Cont;
        false ->
            Cont
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_timer_ack(
    TCID :: term(),
    TID :: term(),
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc timer ack in specified container.
%%--------------------------------------------------------------------
cont_timer_ack(TCID, TID, #timer_container{t_containers = TCont} = Cont) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{timers = [#ts_timer{timer_id = TID}]} ->
            post_ack_process(Cont, TCont, [], TCID);
        #t_container{timers = [#ts_timer{timer_id = TID, timer_type = local} | T]} = TC ->
            LocalTCount = TC#t_container.local_timers,
            TC1 = TC#t_container{state = active, timers = T, local_timers = LocalTCount - 1},
            post_ack_process(Cont, TCont, TC1, TCID);
        #t_container{timers = [#ts_timer{timer_id = TID} | T]} = TC ->
            TC1 = TC#t_container{state = active, timers = T},
            post_ack_process(Cont, TCont, TC1, TCID);
        _else ->
            Cont
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%%===================================================================
%%% EXTEND API
%%%===================================================================

-spec is_exist(TID :: term(), Cont :: timer_container()) -> boolean().
%%--------------------------------------------------------------------
%% @doc is timer exist in default container
%%--------------------------------------------------------------------
is_exist(TID, Cont) ->
    cont_is_exist(?DEFAULT_CONTAINER_ID, TID, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_is_exist(
    TCID :: term(),
    TID :: term(),
    Cont :: timer_container()
) -> boolean().
%%--------------------------------------------------------------------
%% @doc is timer exist in specified container
%%--------------------------------------------------------------------
cont_is_exist(_TCID, _TID, #timer_container{t_containers = []}) ->
    false;
cont_is_exist(TCID, TID, #timer_container{t_containers = TCont}) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{timers = Timers} ->
            lists:keymember(TID, #ts_timer.timer_id, Timers);
        false ->
            false
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec filter_cont(FilterFun :: function(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Removes timers that does not match Fun
%%--------------------------------------------------------------------
filter_cont(FilterFun, #timer_container{t_containers = TCont} = Cont) ->
    TCont2 = [TC || #t_container{id = TCID} = TC <- TCont, FilterFun(TCID) =:= true],
    Cont#timer_container{t_containers = TCont2}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec filter_timers(
    TCID :: term(),
    FTID :: function(),
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Cancel timers in container id that matches Fun
%%--------------------------------------------------------------------
filter_timers(TCID, FTID, #timer_container{t_containers = TCont} = Cont) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{timers = Timers} ->
            case lists:filter(fun(#ts_timer{timer_id = TID}) -> FTID(TID) end, Timers) of
                [_ | _] = TimersToCancel ->
                    lists:foldl(
                        fun
                            (#ts_timer{timer_id = TID}, AccCont) ->
                                cont_cancel_timer(TCID, TID, AccCont);
                            (_, AccCont) ->
                                AccCont
                        end,
                        Cont,
                        TimersToCancel
                    );
                _NoneTimersToCancel ->
                    Cont
            end;
        false ->
            Cont
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec get_timer_info(
    TID :: term(),
    Cont :: timer_container()
) -> undefined | {Time :: non_neg_integer(), Args :: term(), Type :: timer_type()}.
%%--------------------------------------------------------------------
%% @doc Get timer information
%%--------------------------------------------------------------------
get_timer_info(TID, Cont) ->
    cont_get_timer_info(?DEFAULT_CONTAINER_ID, TID, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_get_timer_info(
    TCID :: term(),
    TID :: term(),
    Cont :: timer_container()
) -> undefined | {Time :: non_neg_integer(), Args :: term(), Type :: timer_type()}.
%%--------------------------------------------------------------------
%% @doc Get specific timer information
%%--------------------------------------------------------------------
cont_get_timer_info(_TCID, _TID, #timer_container{t_containers = []}) ->
    undefined;
cont_get_timer_info(TCID, TID, #timer_container{t_containers = TCont}) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{timers = Timers} ->
            case lists:keyfind(TID, #ts_timer.timer_id, Timers) of
                #ts_timer{timer_time = {_, Time2}, timer_arg = Args, timer_type = Type} ->
                    {Time2, Args, Type};
                _ ->
                    undefined
            end;
        false ->
            undefined
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec process_timeout(
    Cont :: timer_container()
) ->
    {none, timer_container()} |
    {wait_timeout, TCID :: term(), TID :: term(), Arg :: term(), Time :: non_neg_integer(), timer_container()} |
    {TCID :: term(), TID :: term(), Arg :: term(), Time :: non_neg_integer(), timer_container()}.
%%--------------------------------------------------------------------
%% @doc Return timer state
%%--------------------------------------------------------------------
process_timeout(#timer_container{t_containers = []} = Cont) ->
    {none, Cont};
process_timeout(#timer_container{t_containers = [#t_container{timers = []} | _]} = Cont) ->
    {none, Cont};
process_timeout(#timer_container{non_blocking = NonBlocking} = Cont) ->
    process_timeout_(NonBlocking, Cont).

process_timeout_(false, Cont) ->
    #timer_container{t_containers = [TC | _]} = Cont,
    #t_container{timers = [Timers | _]} = TC,
    process_timeout__(Cont, TC, Timers);
process_timeout_(true, #timer_container{t_containers = Containers} = Cont) ->
    ActiveContainers = [C || C <- Containers, C#t_container.state =/= wait],
    case ActiveContainers of
        [] -> {none, Cont};
        _ ->
            [#t_container{
                id = TCID,
                local_timers = LocalTCount,
                timers = [
                    #ts_timer{
                        timer_id = TID,
                        timer_time = {TTime1, TTime2},
                        timer_arg = Arg,
                        timer_type = TimerType
                    } | Tail
                ]
            } = TC | _] = ActiveContainers,
            case TTime1 == TTime2 of
                true ->
                    case now_diff(?NOW, TTime1) of
                        X when X >= 0 ->
                            TC1 = TC#t_container{state = wait},
                            NewCont = Cont#timer_container{
                                t_containers = lists:keystore(TCID, #t_container.id, Containers, TC1)
                            },
                            {TCID, TID, Arg, TTime1, NewCont};
                        _ -> {none, Cont}
                    end;
                _ ->
                    OutTimerLCount =
                        case TimerType of
                            local -> LocalTCount - 1;
                            _ -> LocalTCount
                        end,
                    Now = ?NOW,
                    TC1 = TC#t_container{timers = Tail, local_timers = OutTimerLCount},
                    TC2 = add_timer(Now, TID, now_diff(TTime2, Now), Arg, TimerType, TC1),
                    {none, Cont#timer_container{t_containers = update_containers(TC2, Containers)}}
            end
    end.

process_timeout__(Cont, #t_container{state = wait} = TC, #ts_timer{timer_time = {TTime, TTime}} = TS) ->
    #ts_timer{timer_id = TID, timer_arg = Arg} = TS,
    {wait_timeout, TC#t_container.id, TID, Arg, TTime, Cont};
process_timeout__(Cont, TC, #ts_timer{timer_time = {TTime, TTime}} = TS) ->
    case now_diff(?NOW, TTime) of
        X when X >= 0 ->
            #ts_timer{timer_id = TID, timer_arg = Arg} = TS,
            TC1 = TC#t_container{state = wait},
            TCID = TC#t_container.id,
            #timer_container{t_containers = [_ | OtherTCs]} = Cont,
            {TCID, TID, Arg, TTime, Cont#timer_container{t_containers = [TC1 | OtherTCs]}};
        _ ->
            {none, Cont}
    end;
process_timeout__(Cont, TC, TS) ->
    Now = ?NOW,
    #ts_timer{timer_id = TID, timer_arg = Arg, timer_time = {_, TTime2}, timer_type = TT} = TS,
    #timer_container{t_containers = [_ | OtherTCs]} = Cont,
    #t_container{timers = [_ | Tail]} = TC,
    TC1 = add_timer(Now, TID, now_diff(TTime2, Now), Arg, TT, TC#t_container{timers = Tail}),
    {none, Cont#timer_container{t_containers = update_containers(TC1, OtherTCs)}}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec get_actual_timeout(Cont :: timer_container()) -> infinity | non_neg_integer().
%%--------------------------------------------------------------------
%% @doc Return first timeout
%%--------------------------------------------------------------------
get_actual_timeout(#timer_container{t_containers = []}) ->
    infinity;
get_actual_timeout(#timer_container{t_containers = [#t_container{state = wait} | _]}) ->
    ?DEFAULT_WAIT_TIMEOUT;
get_actual_timeout(#timer_container{t_containers = [#t_container{timers = []} | _]}) ->
    infinity;
get_actual_timeout(#timer_container{t_containers = [#t_container{timers = [TS | _]} | _]}) ->
    #ts_timer{timer_time = {T, _}} = TS,
    Diff = now_diff(T, ?NOW),
    if
        Diff < 0 ->
            0;
        true ->
            Diff
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec get_actual_timeout(
    NowTime :: non_neg_integer(),
    Cont :: timer_container()
) -> infinity | non_neg_integer().
%%--------------------------------------------------------------------
%% @doc Return first timeout
%%--------------------------------------------------------------------
get_actual_timeout(_NowTime, #timer_container{t_containers = []}) ->
    infinity;
get_actual_timeout(_NowTime, #timer_container{t_containers = [#t_container{state = wait} | _]}) ->
    ?DEFAULT_WAIT_TIMEOUT;
get_actual_timeout(_NowTime, #timer_container{t_containers = [#t_container{timers = []} | _]}) ->
    infinity;
get_actual_timeout(NowTime, #timer_container{t_containers = [#t_container{timers = [TS | _]} | _]}) ->
    #ts_timer{timer_time = {T, _}} = TS,
    Diff = now_diff(T, NowTime),
    if
        Diff < 0 ->
            0;
        true ->
            Diff
    end.

-spec get_waiting_timeout(
    Cont :: timer_container()
) ->
    {TCID :: term(), TID :: term(), Arg :: term(), Time :: non_neg_integer(), timer_container()} |
    none.
%%--------------------------------------------------------------------
%% @doc Return first wait timeout
%%--------------------------------------------------------------------
get_waiting_timeout(#timer_container{t_containers = [#t_container{id = TCID,
                                            state = wait,
                                            timers = [#ts_timer{timer_id = TID,
                                                timer_time = {TTime, TTime},
                                                timer_arg = Arg} | _]} | _]} = Cont) ->
    {TCID, TID, Arg, TTime, Cont};
get_waiting_timeout(_Cont) ->
    none.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec flush(Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Delete local timer
%%--------------------------------------------------------------------
flush(#timer_container{t_containers = []} = Cont) ->
    Cont;
flush(#timer_container{t_containers = TCont} = Cont) ->
    Cont#timer_container{t_containers = do_flush(TCont)}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec reactivate(Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc function to reactivate last timer in wait state
%%      after calling this function last timer in wait state will expire
%%      again and handle_timeout would be called
%%--------------------------------------------------------------------
reactivate(#timer_container{t_containers = [#t_container{state = wait} = TC | Other]} = Cont) ->
    Cont#timer_container{t_containers = [TC#t_container{state = active} | Other]};
reactivate(#timer_container{} = Cont) ->
    Cont.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec is_container(Cont :: term()) -> boolean().
%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
is_container(TC) ->
    is_record(TC, timer_container).

%%%===================================================================
%%% DEBUG
%%%===================================================================

-spec dbg_info(Cont :: timer_container()) -> {[{Key, Value}], [{Key, Value}]}.
%%--------------------------------------------------------------------
%% @doc Return first wait timeout
%%--------------------------------------------------------------------
dbg_info(Cont) ->
    cont_dbg_info(?DEFAULT_CONTAINER_ID, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_dbg_info(
    TCID :: term(),
    Cont :: timer_container()
) -> {[{Key :: term(), Value :: term()}], [{Key :: term(), Value :: term()}]}.
%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
cont_dbg_info(_TCID, #timer_container{t_containers = []}) ->
    {[], []};
cont_dbg_info(TCID, #timer_container{t_containers = TCont}) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        false ->
            {[], []};
        #t_container{state = State, timers = Timers, wait_timeout = WT} ->
            Tmrs = prepare_timers(Timers, []),
            WT1 =
                case WT of
                    undefined ->
                        undefined;
                    _ ->
                        now_diff(WT, ?NOW) div 1000
                end,
            Common = [{"state", State}, {"wait_timeout", WT1}],
            {Common, Tmrs}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec all_dbg_info(
    Cont :: timer_container()
) -> [{[{Key :: term(), Value :: term()}], [{Key :: term(), Value :: term()}]}] | {[], []}.
%%--------------------------------------------------------------------
%% @doc Return all state of timer_container
%%--------------------------------------------------------------------
all_dbg_info(#timer_container{t_containers = []}) ->
    {[], []};
all_dbg_info(#timer_container{t_containers = TCont}) ->
    F =
        fun(#t_container{state = State, timers = Timers, wait_timeout = WT}, Acc) ->
            Tmrs = prepare_timers(Timers, []),
            WT1 =
                case WT of
                    undefined ->
                        undefined;
                    _ ->
                        now_diff(WT, ?NOW) div 1000
                end,
            Common = [{"state", State}, {"wait_timeout", WT1}],
            [{Common, Tmrs} | Acc]
        end,
    lists:foldl(F, [], TCont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%%===================================================================
%%% MIGRATION
%%%===================================================================

-spec export(Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Delete local timer
%%--------------------------------------------------------------------
export(#timer_container{} = Cont) ->
    flush(Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec import(ImpCont :: timer_container(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc основная мысль - в списке текущих контейнеров делаем сохранение того, что импортируем
%%      при этом заменяем на новые контейнеры при совпадении идентификаторов, затем сортируем
%%--------------------------------------------------------------------
import(#timer_container{t_containers = []}, Cont) ->
    Cont;
import(#timer_container{} = ImpCont, #timer_container{t_containers = TCont} = Cont) ->
    #timer_container{t_containers = ImpTCont} = flush(ImpCont),
    SortedImported = lists:foldl(fun update_containers/2, TCont, ImpTCont),
    Cont#timer_container{t_containers = SortedImported}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_cleanup(TCID :: term(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
cont_cleanup(_TCID, #timer_container{t_containers = []} = Cont) ->
    Cont;
cont_cleanup(TCID, #timer_container{t_containers = [_ | _] = TCont} = Cont) ->
    case lists:keytake(TCID, #t_container.id, TCont) of
        {value, _, TCont2} -> Cont#timer_container{t_containers = TCont2};
        false -> Cont
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_export(TCID :: term(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc Delete by id timer container local timer
%%--------------------------------------------------------------------
cont_export(TCID, #timer_container{} = Cont) ->
    cont_flush(TCID, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_import(ImpCont :: timer_container(), Cont :: timer_container()) -> timer_container().
%%--------------------------------------------------------------------
%% @doc основная мысль - в списке текущих контейнеров делаем сохранение того, что импортируем
%%      при этом заменяем на новые контейнеры при совпадении идентификаторов, затем сортируем
%%--------------------------------------------------------------------
cont_import(#timer_container{t_containers = []}, Cont) ->
    Cont;
cont_import(#timer_container{} = Imp, Cont) ->
    import(Imp, Cont).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

-spec cont_import(
    TCID :: term(),
    ImpCont :: timer_container(),
    Cont :: timer_container()
) -> timer_container().
%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
cont_import(TCID, #timer_container{t_containers = []}, Cont) ->
    cont_cleanup(TCID, Cont);
cont_import(TCID, #timer_container{t_containers = TContainers}, Cont) ->
    #timer_container{t_containers = TCont} = Cont,
    case lists:keyfind(TCID, #t_container.id, TContainers) of
        #t_container{} = TC ->
            case flush_it(TC) of
                #t_container{timers = []} ->
                    cont_cleanup(TCID, Cont);
                FlushedTC ->
                    TCont2 = update_containers(FlushedTC, TCont),
                    Cont#timer_container{t_containers = TCont2}
            end;
        _ ->
            cont_cleanup(TCID, Cont)
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%%===================================================================
%%% Internal functions
%%%===================================================================

delete_t_container(TCID, TContainers) ->
    [TC || #t_container{id = TCIDLocal} = TC <- TContainers, TCIDLocal =/= TCID].
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

now_diff(T2, T1) -> T2 - T1.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

new_now(NowTime, Milliseconds) ->
    NowTime + Milliseconds.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

add_timer(NowTime, TID, D, Arg, TType, TC) when is_integer(D), D > ?VERY_LONG_TIMER ->
    %% для очень длинных (более 49 дней) таймеров делаем чуть иначе
    %% вычисляем timer_time
    TimerTime1 = new_now(NowTime, ?VERY_LONG_TIMER),
    TimerTime2 = new_now(NowTime, D),
    T = #ts_timer{timer_id = TID,
        timer_time = {TimerTime1, TimerTime2},
        timer_arg = Arg,
        timer_type = TType},
    update_timers_in_t_container(TC, T);
add_timer(NowTime, TID, D, Arg, TType, TC) ->
    %% вычисляем timer_time
    TimerTime = new_now(NowTime, D),
    T = #ts_timer{timer_id = TID,
        timer_time = {TimerTime, TimerTime},
        timer_arg = Arg,
        timer_type = TType},
    update_timers_in_t_container(TC, T).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

post_ack_process(Cont, TCont, [], TCID) ->
    Cont#timer_container{t_containers = delete_t_container(TCID, TCont)};
post_ack_process(Cont, TCont, TC, _TCID) ->
    Cont#timer_container{t_containers = update_containers(TC, TCont)}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

update_containers(TC, Containers) ->
    update_containers(Containers, TC, false).
update_containers([], TC, _DuplicateRemoved) -> [TC];
update_containers([#t_container{id = Id} | TCont], #t_container{id = Id} = TC, false) ->
    update_containers(TCont, TC, true);
update_containers([#t_container{timers = []} | TCont], TC, DuplicateRemoved) ->
    update_containers(TCont, TC, DuplicateRemoved);
update_containers([#t_container{timers = [#ts_timer{timer_time = {CT, _}} | _]} = CTC | TCont],
    #t_container{timers = [#ts_timer{timer_time = {T, _}} | _]} = TC, DuplicateRemoved) when T < CT ->
    case DuplicateRemoved of
        true ->
            [TC, CTC | TCont];
        false ->
            [TC, CTC | lists:keydelete(TC#t_container.id, #t_container.id, TCont)]
    end;
update_containers([#t_container{} = CTC | TCont], TC, DuplicateRemoved) ->
    [CTC | update_containers(TCont, TC, DuplicateRemoved)].
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

add_timer_tail(NowTime, TID, D, Arg, TType, TC) ->
    #t_container{timers = Timers, local_timers = TimerLCount} = TC,
    {TimerTime1, TimerTime2} = add_timer_tail(NowTime, D),
    T = #ts_timer{timer_id = TID,
        timer_time = {TimerTime1, TimerTime2},
        timer_arg = Arg,
        timer_type = TType
    },
    OutTimerLCount = case TType of local -> TimerLCount + 1; _ -> TimerLCount end,
    NewTimers = lists:keysort(#ts_timer.timer_time, [T | Timers]),
    TC#t_container{timers = NewTimers, local_timers = OutTimerLCount}.

add_timer_tail(NowTime, D) when is_integer(D), D > ?VERY_LONG_TIMER ->
    {new_now(NowTime, ?VERY_LONG_TIMER), new_now(NowTime, D)};
add_timer_tail(NowTime, D) ->
    TimerTime = new_now(NowTime, D),
    {TimerTime, TimerTime}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

update_timers_in_t_container(TC, Timer) ->
    #ts_timer{timer_type = TimerType} = Timer,
    #t_container{timers = Timers, local_timers = TimerLCount} = TC,
    case {update_timers(Timers, Timer, undefined), TimerType} of
        {{NewTimers, #ts_timer{timer_type = local}}, local} ->
            TC#t_container{timers = NewTimers};
        {{NewTimers, #ts_timer{timer_type = local}}, _} ->
            TC#t_container{timers = NewTimers, local_timers = TimerLCount - 1};
        {{NewTimers, _}, local} ->
            TC#t_container{timers = NewTimers, local_timers = TimerLCount + 1};
        {{NewTimers, _}, _} ->
            TC#t_container{timers = NewTimers}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

update_timers([], T, RemovedTimer) ->
    {[T], RemovedTimer};
update_timers([#ts_timer{timer_id = Id} = RemovedTimer | Timers], #ts_timer{timer_id = Id} = T, undefined) ->
    update_timers(Timers, T, RemovedTimer);
update_timers([CT | Timers], T, RemovedTimer) ->
    #ts_timer{timer_time = CTime} = CT,
    #ts_timer{timer_time = Time} = T,
    case Time < CTime of
        true ->
            case RemovedTimer of
                undefined ->
                    case lists:keytake(T#ts_timer.timer_id, #ts_timer.timer_id, Timers) of
                        {value, ResultRemovedTimer, OtherTimers} ->
                            {[T, CT | OtherTimers], ResultRemovedTimer};
                        _ ->
                            {[T, CT | Timers], undefined}
                    end;
                _ ->
                    {[T, CT | Timers], RemovedTimer}
            end;
        false ->
            {ResultList, ResultRemovedTimer} = update_timers(Timers, T, RemovedTimer),
            {[CT | ResultList], ResultRemovedTimer}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

delete_timer(_TID, #t_container{timers = []}) ->
    not_found;
delete_timer(TID, #t_container{timers = [#ts_timer{timer_id = TID, timer_type = local} | OtherTimers]} = TC) ->
    #t_container{local_timers = LocalCTimers} = TC,
    {resort, TC#t_container{timers = OtherTimers, local_timers = LocalCTimers - 1}};
delete_timer(TID, #t_container{timers = [#ts_timer{timer_id = TID} | OtherTimers]} = TC) ->
    {resort, TC#t_container{timers = OtherTimers}};
delete_timer(TID, #t_container{timers = Timers, local_timers = LocalCTimers} = TC) ->
    case lists:keytake(TID, #ts_timer.timer_id, Timers) of
        {value, #ts_timer{timer_type = local}, OtherTimers} ->
            {ok, TC#t_container{timers = OtherTimers, local_timers = LocalCTimers - 1}};
        {value, #ts_timer{}, OtherTimers} ->
            {ok, TC#t_container{timers = OtherTimers}};
        _ ->
            not_found
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

prepare_timers([], Res) ->
    lists:reverse(Res);
prepare_timers([#ts_timer{timer_id = TID, timer_time = {_, TT}, timer_arg = TA} | T], Res) ->
    Ex = now_diff(TT, ?NOW),
    Str = [{"TID", TID}, {"TimeToExpire", Ex}, {"Args", TA}],
    prepare_timers(T, [Str | Res]).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

do_flush([]) ->
    [];
do_flush([H | T]) ->
    case flush_it(H) of
        #t_container{timers = []} ->
            do_flush(T);
        H1 ->
            [H1 | do_flush(T)]
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

flush_it(#t_container{local_timers = 0} = TCont) -> TCont;
flush_it(#t_container{timers = Timers} = TCont) ->
    Timers1 = [Timer || Timer = #ts_timer{timer_type = Type} <- Timers, Type /= local],
    TCont#t_container{timers = Timers1, local_timers = 0}.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

cont_flush(_TCID, #timer_container{t_containers = []}) ->
    #timer_container{t_containers = []};
cont_flush(TCID, #timer_container{t_containers = TCont} = Cont) ->
    case lists:keyfind(TCID, #t_container.id, TCont) of
        #t_container{} = TC ->
            case flush_it(TC) of
                #t_container{timers = []} ->
                    Cont#timer_container{t_containers = []};
                TCont1 ->
                    Cont#timer_container{t_containers = [TCont1]}
            end;
        false ->
            #timer_container{t_containers = []}
    end.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

now_us({MegaSecs, Secs, MicroSecs}) ->
    (MegaSecs * 1000000 + Secs) * 1000 + MicroSecs div 1000.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
