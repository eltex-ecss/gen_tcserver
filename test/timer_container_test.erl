-module(timer_container_test).

-include_lib("eunit/include/eunit.hrl").

run_test_() ->
    [{"Get actual timeout", fun get_actual_timeout_/0},
     {"Get waiting timeout", fun get_waiting_timeout_/0},
     {"Timer ACK", fun timer_ack_/0},
     {"Container timer ACK", fun cont_timer_ack_/0},
     {"Is timer exist", fun is_exist_/0},
     {"Container is timer exist", fun cont_is_exist_/0},
     {"Cancel timer", fun cancel_timer_/0},
     {"Container cancel timer", fun cont_cancel_timer_/0},
     {"Container cancel timers", fun cont_cancel_timers_/0},
     {"Reactivate", fun reactivate_/0},
     {"Flush", fun flush_/0},
     {"Export and import", fun export_import_/0},
     {"Container cleanup", fun cont_cleanup_/0},
     {"Sort containers", fun sort_containers_/0},
     {"Cancel after ack", fun cancel_after_ack_/0},
     {"Cancel with equivalent id", fun cancel_equal_id_/0},
     {"Filter timer containers", fun filter_cont_/0},
     {"Filter timers", fun filter_timers_/0},
     {"Non blocking ack", fun non_blocking_ack_/0},
     {"Start obsolete timer in wait TC state #1", fun obsolete_timer_in_wait_tc_state_1_/0},
     {"Start obsolete timer in wait TC state #2", fun obsolete_timer_in_wait_tc_state_2_/0}
    ].

performance_test_() ->
    {setup,
        % Setup fun
        fun() -> ok end,
        % Destruct fun
        fun(_) -> ok end,
        {inorder,
            [
                {"Performance test 1", timeout, 15, fun performance_1_t/0},
                {"Performance test 2", timeout, 15, fun performance_2_t/0},
                {"Performance test 3", timeout, 15, fun performance_3_t/0},
                {"Performance test 4", timeout, 15, fun performance_4_t/0},
                {"Performance test 5", timeout, 15, fun performance_5_t/0},
                {"Performance test 6", timeout, 15, fun performance_6_t/0}
            ]
        }
    }.

get_actual_timeout_() ->
    TS = timer_container:init([]),
    ?assertEqual(infinity, timer_container:get_actual_timeout(TS)),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    timer:sleep(20),
    ?assertEqual(0, timer_container:get_actual_timeout(NewTS)).

get_waiting_timeout_() ->
    TS = timer_container:init([]),
    ?assertEqual(none, timer_container:get_waiting_timeout(TS)),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    timer:sleep(20),
    {_, timer1, [], _, NewTS1} = timer_container:process_timeout(NewTS),
    ?assertMatch({_, timer1, [], _, _}, timer_container:get_waiting_timeout(NewTS1)).

timer_ack_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    ?assertEqual({none, NewTS}, timer_container:process_timeout(NewTS)),
    timer:sleep(20),
    {_, timer1, [], _, NewTS1} = timer_container:process_timeout(NewTS),
    ?assertEqual(TS, timer_container:timer_ack(NewTS1)).

cont_timer_ack_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:cont_start_timer(cont1, timer1, 10, [], TS),
    ?assertEqual({none, NewTS}, timer_container:process_timeout(NewTS)),
    timer:sleep(20),
    {cont1, timer1, [], _, NewTS1} = timer_container:process_timeout(NewTS),
    ?assertEqual(TS, timer_container:cont_timer_ack(cont1, NewTS1)).

is_exist_() ->
    TS = timer_container:init([]),
    ?assertEqual(false, timer_container:is_exist(timer1, TS)),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    ?assertEqual(true, timer_container:is_exist(timer1, NewTS)).

cont_is_exist_() ->
    TS = timer_container:init([]),
    ?assertEqual(false, timer_container:cont_is_exist(cont1, timer1, TS)),
    NewTS = timer_container:cont_start_timer(cont1, timer1, 10, [], TS),
    ?assertEqual(true, timer_container:cont_is_exist(cont1, timer1, NewTS)).

cancel_timer_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    ?assertEqual(TS, timer_container:cancel_timer(timer1, NewTS)).

cont_cancel_timer_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:cont_start_timer(cont1, timer1, 10, [], TS),
    ?assertEqual(TS, timer_container:cont_cancel_timer(cont1, timer1, NewTS)).

cont_cancel_timers_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:cont_start_timer(cont1, timer1, 10, [], TS),
    NewTS1 = timer_container:cont_start_timer(cont1, timer2, 10, [], NewTS),
    ?assertEqual(TS, timer_container:cont_cancel_timers(cont1, NewTS1)).

reactivate_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:start_timer(timer1, 10, [], TS),
    timer:sleep(20),
    {_, timer1, [], _, NewTS1} = timer_container:process_timeout(NewTS),
    ?assertEqual(NewTS, timer_container:reactivate(NewTS1)).

flush_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:start_timer_local(timer1, 10, [], TS),
    ?assertEqual(TS, timer_container:flush(NewTS)).

export_import_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:start_timer(timer, 20, [], TS),
    NewTS1 = timer_container:start_timer_local(timer1, 10, [], NewTS),
    ExportedNewTS = timer_container:export(NewTS1),
    ImportedNewTS = timer_container:import(ExportedNewTS, TS),
    ?assertEqual(NewTS, ImportedNewTS).

cont_cleanup_() ->
    TS = timer_container:init([]),
    NewTS = timer_container:cont_start_timer(cont1, timer1, 10, [], TS),
    ?assertEqual(TS, timer_container:cont_cleanup(cont1, NewTS)).

sort_containers_() ->
    Timers = [
        {cont1, timer1, 30}, {cont1, timer2, 40},
        {cont2, timer1, 10}, {cont2, timer2, 20},
        {cont3, timer1, 60}, {cont3, timer2, 70}
    ],
    TS = init_timers(Timers, []),
    timer:sleep(15),
    {CT, NewTS} = process_timeout(TS),
    ?assertEqual({cont2, timer1}, CT),

    timer:sleep(10),
    {CT1, NewTS1} = process_timeout(NewTS),
    ?assertEqual({cont2, timer2}, CT1),

    timer:sleep(10),
    {CT2, NewTS2} = process_timeout(NewTS1),
    ?assertEqual({cont1, timer1}, CT2),

    timer:sleep(10),
    {CT3, NewTS3}  = process_timeout(NewTS2),
    ?assertEqual({cont1, timer2}, CT3),

    timer:sleep(70),
    {CT4, NewTS4}  = process_timeout(NewTS3),
    ?assertEqual({cont3, timer1}, CT4),
    {CT5, _}  = process_timeout(NewTS4),
    ?assertEqual({cont3, timer2}, CT5).

cancel_after_ack_() ->
    Timers = [{cont1, timer1, 20}, {cont2, timer1, 40}, {cont2, timer2, 50}],
    TS = init_timers(Timers, []),

    timer:sleep(30),
    {cont1, timer1, [], _, NewTS} = timer_container:process_timeout(TS),
    NewTS1 = timer_container:cont_cancel_timer(cont2, timer1, NewTS),

    timer:sleep(30),
    ?assertMatch({wait_timeout, cont1, timer1, [], _, NewTS1}, timer_container:process_timeout(NewTS1)).

cancel_equal_id_() ->
    Timers = [{cont1, timer1, 20}, {cont2, timer1, 40}],
    TS = init_timers(Timers, []),

    NewTS = timer_container:cont_cancel_timer(cont1, timer1, TS),
    timer:sleep(50),
    {CT, _NewTS1}  = process_timeout(NewTS),
    ?assertEqual({cont2, timer1}, CT).

filter_cont_() ->
    Timers = [{cont1, timer1, 10}, {cont2, timer2, 20}, {cont3, timer3, 30}, {cont4, timer4, 40}],
    TS = init_timers(Timers, []),
    TS2 = timer_container:filter_cont(fun(TCID) -> TCID =:= cont2 orelse TCID =:= cont4 end, TS),
    timer:sleep(50),
    {CT1, TS3}  = process_timeout(TS2),
    ?assertEqual({cont2, timer2}, CT1),
    {CT2, _TS4}  = process_timeout(TS3),
    ?assertEqual({cont4, timer4}, CT2).

filter_timers_() ->
    Timers = [{cont1, timer1, 10}, {cont1, timer2, 20}, {cont1, timer3, 30}, {cont2, timer4, 40}],
    TS = init_timers(Timers, []),
    TS2 = timer_container:filter_timers(cont1, fun(TimerID) -> TimerID =:= timer1 orelse TimerID =:= timer3 end, TS),
    timer:sleep(50),
    {CT1, TS3}  = process_timeout(TS2),
    ?assertEqual({cont1, timer2}, CT1),
    {CT2, _TS4}  = process_timeout(TS3),
    ?assertEqual({cont2, timer4}, CT2).

non_blocking_ack_() ->
    Timers = [
        {cont1, timer1, 20}, {cont1, timer2, 30},
        {cont2, timer1, 40}, {cont2, timer2, 50}, {cont2, timer3, 60}
    ],
    TS = init_timers(Timers, [non_blocking]),

    timer:sleep(30),
    {cont1, timer1, [], _, NewTS} = timer_container:process_timeout(TS),
    NewTS1 = timer_container:cont_cancel_timer(cont2, timer1, NewTS),

    timer:sleep(30),
    {cont2, timer2, [], _, NewTS2} = timer_container:process_timeout(NewTS1),
    NewTS3 = timer_container:cont_timer_ack(cont2, NewTS2),
    timer:sleep(30),
    ?assertMatch({cont2, timer3, [], _, _}, timer_container:process_timeout(NewTS3)).

obsolete_timer_in_wait_tc_state_1_() ->
    Now = erlang:timestamp(),
    TS1 = timer_container:init([], [non_blocking]),
    TS2 = timer_container:cont_start_timer(Now, cont1, timer1, 10, [], TS1),
    TS3 = timer_container:cont_start_timer(Now, cont1, timer2, 20, [], TS2),
    timer:sleep(30),
    {cont1, timer1, [], _, TS4} = timer_container:process_timeout(TS3),
    % В состоянии wait_ack поставить новый таймер в голову НЕЛЬЗЯ
    ?assertError({error, {obsolete_timer, {cont1, obsolete_timer1}}}, timer_container:cont_start_timer(Now, cont1, obsolete_timer1, 5, [], TS4)),
    TS5 = timer_container:cont_timer_ack(cont1, timer1, TS4),
    % Пока таймер не сработал, в голову таймер поставить можно.
    TS6 = timer_container:cont_start_timer(Now, cont1, obsolete_timer2, 5, [], TS5),
    ?assertMatch({cont1, obsolete_timer2, [], _, _}, timer_container:process_timeout(TS6)).

obsolete_timer_in_wait_tc_state_2_() ->
    Now = erlang:timestamp(),
    TS1 = timer_container:init([], [non_blocking]),
    TS2 = timer_container:cont_start_timer(Now, cont1, timer1, 10, [], TS1),
    TS3 = timer_container:cont_start_timer(Now, cont1, timer2, 20, [], TS2),
    timer:sleep(30),
    {cont1, timer1, [], _, TS4} = timer_container:process_timeout(TS3),
    % В состоянии wait_ack поставить новый таймер в голову НЕЛЬЗЯ
    % Пока таймер не сработал, в голову таймер поставить можно.
    TS5 = timer_container:cont_start_timer(Now, cont1, obsolete_timer1, 10, [], TS4),
    TS6 = timer_container:cont_timer_ack(cont1, timer1, TS5),
    ?assertMatch({cont1, obsolete_timer1, [], _, _}, timer_container:process_timeout(TS6)).

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_1_t() ->
    GenTimerFun =
        fun(N) ->
            {timer, N}
        end,
    GenTContainerFun =
        fun(N) ->
            TContId = {cont, N},
            [{TContId, TimerId, 50} || TimerId <- lists:map(GenTimerFun, lists:seq(1, 1000))]
        end,
    Timers = lists:append(lists:map(GenTContainerFun, lists:seq(1, 100))),
    IStartTime = erlang:timestamp(),
    TS = init_timers(Timers, []),
    IStopTime = erlang:timestamp(),
    % Old TC result 3771525 -> 3667683 -> 3253794
    ?debugFmt("Init time 1: ~p~n", [timer:now_diff(IStopTime, IStartTime)]),
    timer:sleep(100),
    CheckFun =
        fun(F, TSLocal, AccIn) ->
            case timer_container:process_timeout(TSLocal) of
                {none, _} ->
                    {TSLocal, AccIn};
                {ContId, TimerId, [], _, TSLocal1} ->
                    LTimers = proplists:get_value(ContId, AccIn, []),
                    AccOut = lists:keystore(ContId, 1, AccIn, {ContId, [TimerId | LTimers]}),
                    TSOut = timer_container:cont_timer_ack(ContId, TimerId, TSLocal1),
                    F(F, TSOut, AccOut)
            end
        end,
    StartTime = erlang:timestamp(),
    {_TSOut, OutTimers} = CheckFun(CheckFun, TS, []),
    StopTime = erlang:timestamp(),
    % Old TC result 2186362 -> 436125 -> 427127.
    ?debugFmt("Execute time 1: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    ?assertEqual(100, erlang:length(OutTimers)),
    CheckFun2 =
        fun({_, CTimers}) ->
            ?assertEqual(1000, erlang:length(CTimers))
        end,
    lists:foreach(CheckFun2, OutTimers),
    ok.
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_2_t() ->
    GenTimerFun =
        fun(N) ->
            {timer, N}
        end,
    GenTContainerFun =
        fun(N) ->
            TContId = {cont, N},
            [{TContId, TimerId, 50} || TimerId <- lists:map(GenTimerFun, lists:seq(1, 1000))]
        end,
    Timers = lists:append(lists:map(GenTContainerFun, lists:seq(1, 100))),
    TS = init_timers(Timers, []),
    CancelTimerFun =
        fun({TCID, TID, _}, TCont) ->
            timer_container:cont_cancel_timer(TCID, TID, TCont)
        end,
    StartTime = erlang:timestamp(),
    TSOut = lists:foldl(CancelTimerFun, TS, Timers),
    StopTime = erlang:timestamp(),
    % Old TC result 2186362 -> 30506 -> 33047.
    ?debugFmt("Cancel time 2: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    CheckTimerNotExistsFun =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TSOut))
        end,
    lists:foreach(CheckTimerNotExistsFun, Timers).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_3_t() ->
    GenTimerFun =
        fun(N) ->
            {timer, N}
        end,
    GenTContainerFun =
        fun(N) ->
            TContId = {cont, N},
            [{TContId, TimerId, 50} || TimerId <- lists:map(GenTimerFun, lists:seq(1, 1000))]
        end,
    Timers = lists:append(lists:map(GenTContainerFun, lists:seq(1, 100))),
    TS = init_timers(Timers, []),
    CancelTimerFun =
        fun({TCID, TID, _}, TCont) ->
            timer_container:cont_cancel_timer(TCID, TID, TCont)
        end,
    RevercedTimers = lists:reverse(Timers),
    StartTime = erlang:timestamp(),
    TSOut = lists:foldl(CancelTimerFun, TS, RevercedTimers),
    StopTime = erlang:timestamp(),
    % Old TC result 2186362 -> 1539719 -> 1457343.
    ?debugFmt("Cancel time 3: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    CheckTimerNotExistsFun =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TSOut))
        end,
    lists:foreach(CheckTimerNotExistsFun, Timers).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_4_t() ->
    {_, [Timers]} = file:consult("./../test/timers.list"),
    IStartTime = erlang:timestamp(),
    TS = init_timers(Timers, []),
    IStopTime = erlang:timestamp(),
    % Old TC result 3210756 -> 2389085 -> 2057102
    ?debugFmt("Init time 4: ~p~n", [timer:now_diff(IStopTime, IStartTime)]),
    CancelTimerFun =
        fun({TCID, TID, _}, TCont) ->
            timer_container:cont_cancel_timer(TCID, TID, TCont)
        end,
    RevercedTimers = lists:reverse(Timers),
    StartTime = erlang:timestamp(),
    TSOut = lists:foldl(CancelTimerFun, TS, RevercedTimers),
    StopTime = erlang:timestamp(),
    % Old TC result 2186362 -> 476394 -> 365593.
    ?debugFmt("Cancel time 4: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    CheckTimerNotExistsFun =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TSOut))
        end,
    lists:foreach(CheckTimerNotExistsFun, Timers).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_5_t() ->
    {_, [Timers]} = file:consult("./../test/timers.list"),
    IStartTime = erlang:timestamp(),
    TS = init_timers(Timers, []),
    IStopTime = erlang:timestamp(),
    % Old TC result 2053239
    ?debugFmt("Init time 5: ~p~n", [timer:now_diff(IStopTime, IStartTime)]),
    ExecuteTimerFun =
        fun({_TCID, _TID, _}, TSLocal) ->
            case timer_container:process_timeout(TSLocal) of
                {none, _} ->
                    TSLocal;
                {ContId, TimerId, [], _, TSLocal1} ->
                    timer_container:cont_timer_ack(ContId, TimerId, TSLocal1)
            end
        end,
    RevercedTimers = lists:reverse(Timers),
    StartTime = erlang:timestamp(),
    TSOut = lists:foldl(ExecuteTimerFun, TS, RevercedTimers),
    StopTime = erlang:timestamp(),
    % Old TC result 95533
    ?debugFmt("Execute time 5: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    CheckTimerNotExistsFun =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TSOut))
        end,
    lists:foreach(CheckTimerNotExistsFun, Timers),
    FStartTime = erlang:timestamp(),
    TS2 = timer_container:flush(TS),
    FStopTime = erlang:timestamp(),
    % Old TC result 2189 -> 10
    ?debugFmt("Flush time 5: ~p~n", [timer:now_diff(FStopTime, FStartTime)]),
    CheckTimerNotExistsFun2 =
        fun({TCID, TID, _}) ->
            ?assertEqual(true, timer_container:cont_is_exist(TCID, TID, TS2))
        end,
    lists:foreach(CheckTimerNotExistsFun2, Timers).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%--------------------------------------------------------------------
%% @doc
%%--------------------------------------------------------------------
performance_6_t() ->
    {_, [Timers]} = file:consult("./../test/timers.list"),
    IStartTime = erlang:timestamp(),
    TS = init_local_timers(Timers, []),
    IStopTime = erlang:timestamp(),
    % Old TC result 2081973
    ?debugFmt("Init time 6: ~p~n", [timer:now_diff(IStopTime, IStartTime)]),
    ExecuteTimerFun =
        fun({_TCID, _TID, _}, TSLocal) ->
            case timer_container:process_timeout(TSLocal) of
                {none, _} ->
                    TSLocal;
                {ContId, TimerId, [], _, TSLocal1} ->
                    timer_container:cont_timer_ack(ContId, TimerId, TSLocal1)
            end
        end,
    RevercedTimers = lists:reverse(Timers),
    StartTime = erlang:timestamp(),
    TSOut = lists:foldl(ExecuteTimerFun, TS, RevercedTimers),
    StopTime = erlang:timestamp(),
    % Old TC result 94848
    ?debugFmt("Execute time 6: ~p~n", [timer:now_diff(StopTime, StartTime)]),
    CheckTimerNotExistsFun =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TSOut))
        end,
    lists:foreach(CheckTimerNotExistsFun, Timers),
    FStartTime = erlang:timestamp(),
    TS2 = timer_container:flush(TS),
    FStopTime = erlang:timestamp(),
    % Old TC result 2006
    ?debugFmt("Flush time 6: ~p~n", [timer:now_diff(FStopTime, FStartTime)]),
    CheckTimerNotExistsFun2 =
        fun({TCID, TID, _}) ->
            ?assertEqual(false, timer_container:cont_is_exist(TCID, TID, TS2))
        end,
    lists:foreach(CheckTimerNotExistsFun2, Timers).
%%++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++

%%%
%%% HELPERS
%%%
process_timeout(TS) ->
    {Cont, Timer, [], _, NewTS} = timer_container:process_timeout(TS),
    {{Cont, Timer}, timer_container:cont_timer_ack(Cont, NewTS)}.


init_timers(Timers, Args) ->
    TS = timer_container:init([], Args),
    lists:foldl(
    fun({Cont, Timer, Time}, Acc) ->
        timer_container:cont_start_timer(Cont, Timer, Time, [], Acc)
    end, TS, Timers).

init_local_timers(Timers, Args) ->
    TS = timer_container:init([], Args),
    lists:foldl(
        fun({Cont, Timer, Time}, Acc) ->
            timer_container:cont_start_timer_local(Cont, Timer, Time, [], Acc)
        end, TS, Timers).
