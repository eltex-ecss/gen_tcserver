<p align="center">
<img src="https://raw.githubusercontent.com/eltex-ecss/gen_tcserver/master/doc/gen_tcserver.jpg"/>
</p>

## Overview
gen_tcserver это behaviour, который реализован на основе gen server-a. Он расширяет возможности gen server-а, добавляя возможность работы с таймерами и соответствующи на них реагировать.

## Usages
Для работы с gen_tcserver нужно указать:
```erlang
-behaviour(gen_tcserver).
```
Добавить реализацию методов:
```erlang
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
```

## timer container API:


```erlang
TID :: term()                            = Уникальное имя таймера
Duration :: non_neg_integer()            = Время жизни таймера
Args :: [{Key :: term(), Val :: term()}] = Данные устонавливаемые при инициализации хранилища таймеров
Arg  :: term()                           = Данные получаемые по истечению таймера
Time1 :: non_neg_integer()               = Время старта
Time2 :: non_neg_integer()               = Время срабатывания
Cont = ImpCont :: timer_container()      = Хранилище таймеров
NowTime :: non_neg_integer()             = Собственное время, когда стартовал таймер
TCID :: term()                           = Уникальная группа, по которой объединяются таймера
```

Таймер идентифицируется на таймер сервере идентификатором TID, задаваемым пользователем. Введение системы идентификации таймеров полностью перекладывается на плечи пользователя. Забота о том, чтобы у разных пользовательских таймеров не совпали TID, так же целиком и полностью возлагается на пользователя.

Таймера могут быть локальными или глобальными. Когда таймер локальный, на него действует дополнительный ряд функций по очистке таймеров. 

Таймер сервер запускается и работает в отдельном процессе, фактически является реализацией gen_fsm из 2х состояний:
active, wait.
1. В состоянии active производится ожидание истечения очередного таймера. Таймера могут запускаться, останавливаться, рестартоваться.
2. В состоянии wait процесс находится при истечении очередного таймера, когда для него был вызван timer_fun и пользователь выполняет действия по обработке таймера. В этом состоянии таймера могут запускаться, останавливаться, рестартоваться. Переход из этого состояния в active осуществляется по событию timer_ack.

Замечания:
1. Хранилице таймеров инициализируется в init. 
2. Сами таймера взводятся в handle_call, handle_cast, handle_info. 
3. Результат их завершения обрабатывается handle_timeout. 
4. На завершение таймеров нужно реагировать с помощью timer_ack.
5. Длительность таймера задается в миллисекундах.

Для работы с таймерами существует следующее API:

Инициализирует хранилище таймеров.
```erlang
init(Cont | [])
init(Cont, Args)

retutn NewCont
```

Взводит таймер.
```erlang
start_timer(TID, Duration, Arg, Cont)
start_timer(NowTime, TID, Duration, Arg, Cont)
cont_start_timer(TCID, TID, Duration, Arg, Cont)
cont_start_timer(NowTime, TCID, TID, Duration, Arg, Cont)

retutn NewCont
```

Взводит локальный таймер.
```erlang
start_timer_local(TID, Duration, Arg, Cont)
start_timer_local(NowTime, TID, Duration, Arg, Cont)
cont_start_timer_local(TCID, TID, Duration, Arg, Cont)
cont_start_timer_local(NowTime, TCID, TID, Duration, Arg, Cont)

retutn NewCont
```

Отменяет таймер или группу таймеров.
```erlang
cancel_timer(TID, Cont)
cont_cancel_timer(TCID, TID, Cont)
cont_cancel_timers(TCID, Cont)

retutn NewCont
```

Если таймер сработал, то его требуется подтвердить. Данный метод подтверждает его. Если таймер не сработал, ничего не делает.
```erlang
timer_ack(Cont) - подтверждает первый сработавший
cont_timer_ack(TCID, Cont) - подтверждает первый сработавший в группе
cont_timer_ack(TCID, TID, Cont) - подтверждает определенный таймер

retutn NewCont
```

Проверяет на существование таймера.
```erlang
is_exist(TID, Cont)
cont_is_exist(TCID, TID, Cont)

retutn boolean()
```

Удаляет таймера, которые не соответствуют фильтрующей функции.
```erlang
filter_cont(FilterFun, Cont)

retutn NewCont
```

Отменяет таймера, которые соответствуют фильтрующей функции.
```erlang
filter_timers(TCID, FTID, Cont)

retutn NewCont
```

Возвращает информацию о таймере.
```erlang
get_timer_info(TID, Cont)
cont_get_timer_info(TCID, TID, Cont)

retutn undefined | {Time2, Args, Type :: local | global}
```

Возвращает состояние таймера.
```erlang
process_timeout(Cont)

return {none, timer_container()} |
       {wait_timeout, TCID, TID, Arg, TTime1, NewCont} |
       {TCID, TID, Arg, TTime1, NewCont}.
```

Возвращает время до срабатывания таймера.
```erlang
get_actual_timeout(Cont)
get_actual_timeout(NowTime, Cont)

return infinity | non_neg_integer()
```

Возвращает таймер сработавший, но не получивший timer_ack.
```erlang
get_waiting_timeout(Cont)

return {TCID, TID, Arg, TTime2, NewCont} | none.
```

Удаляет локальные таймера.
```erlang
flush(Cont)

return NewCont
```

Реактивирует таймер, который находится в режиме ожидания timer_ack.
```erlang
reactivate(Cont)

return NewCont
```

Проверяет что это хранилище таймеров.
```erlang
is_container(Data :: term())

return boolean()
```

## Migration timers API:

Удаляет локальные таймера.
```erlang
export(Cont)
cont_export(TCID, Cont)

return NewCont
```

```erlang
import(ImpCont, Cont)
cont_import(ImpCont, Cont)
cont_import(TCID, ImpCont, Cont)

return NewCont
```

```erlang
cont_cleanup(TCID, Cont)

return NewCont
```
