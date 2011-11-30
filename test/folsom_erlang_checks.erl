%%%
%%% Copyright 2011, Boundary
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%


%%%-------------------------------------------------------------------
%%% File:      folsom_erlang_checks.erl
%%% @author    joe williams <j@boundary.com>
%%% @doc
%%% @end
%%%------------------------------------------------------------------

-module(folsom_erlang_checks).

-include_lib("eunit/include/eunit.hrl").

-export([
         create_metrics/0,
         populate_metrics/0,
         check_metrics/0,
         delete_metrics/0,
         vm_metrics/0,
         counter_metric/2
        ]).

-define(DATA, [1, 5, 10, 100, 200, 500, 750, 1000, 2000, 5000]).

-define(DATA1, [5, 10, 15, 20, 25, 30, 35, 40, 45, 50]).

-include("folsom.hrl").

create_metrics() ->
    ok = folsom_metrics:new_counter(counter),
    ok = folsom_metrics:new_gauge(<<"gauge">>),

    ok = folsom_metrics:new_histogram(<<"uniform">>, uniform, 5000, 1),
    ok = folsom_metrics:new_histogram(exdec, exdec, 5000, 1),
    ok = folsom_metrics:new_histogram(none, none, 5000, 1),

    ok = folsom_metrics:new_histogram(nonea, none, 5000, 1),

    ok = folsom_metrics:new_histogram(timed, none, 5000, 1),

    ok = folsom_metrics:new_history(<<"history">>),
    ok = folsom_metrics:new_meter(meter),

    ?debugFmt("ensuring meter tick is registered with gen_server~n", []),
    ok = ensure_meter_tick_exists(meter),

    ?debugFmt("ensuring multiple timer registrations dont cause issues", []),
    ok = folsom_meter_timer_server:register(meter),
    ok = folsom_meter_timer_server:register(meter),
    ok = folsom_meter_timer_server:register(meter),

    ?debugFmt("~p", [folsom_meter_timer_server:dump()]),
    {state, List} = folsom_meter_timer_server:dump(),
    1 = length(List),

    9 = length(folsom_metrics:get_metrics()),

    ?debugFmt("~n~nmetrics: ~p~n", [folsom_metrics:get_metrics()]).

populate_metrics() ->
    ok = folsom_metrics:notify({counter, {inc, 1}}),
    ok = folsom_metrics:notify({counter, {dec, 1}}),

    ok = folsom_metrics:notify({<<"gauge">>, 2}),

    [ok = folsom_metrics:notify({<<"uniform">>, Value}) || Value <- ?DATA],
    [ok = folsom_metrics:notify({exdec, Value}) || Value <- ?DATA],
    [ok = folsom_metrics:notify({none, Value}) || Value <- ?DATA],

    [ok = folsom_metrics:notify({nonea, Value}) || Value <- ?DATA1],

    3.141592653589793 = folsom_metrics:histogram_timed_update(timed, math, pi, []),

    ok = folsom_metrics:notify({<<"history">>, "string"}),

    {error, _, nonexistant_metric} = folsom_metrics:notify({historya, "5"}),
    ok = folsom_metrics:notify(historya, <<"binary">>, history),

    % simulate an interval tick
    folsom_metrics_meter:tick(meter),

    [ok,ok,ok,ok,ok] = [ folsom_metrics:notify({meter, Item}) || Item <- [100, 100, 100, 100, 100]],

    % simulate an interval tick
    folsom_metrics_meter:tick(meter).

check_metrics() ->
    0 = folsom_metrics:get_metric_value(counter),

    2 = folsom_metrics:get_metric_value(<<"gauge">>),

    Histogram1 = folsom_metrics:get_histogram_statistics(<<"uniform">>),
    histogram_checks(Histogram1),
    Histogram2 = folsom_metrics:get_histogram_statistics(exdec),
    histogram_checks(Histogram2),
    Histogram3 = folsom_metrics:get_histogram_statistics(none),
    histogram_checks(Histogram3),

    CoValues = folsom_metrics:get_histogram_statistics(none, nonea),
    histogram_co_checks(CoValues),

    List = folsom_metrics:get_metric_value(timed),
    ?debugFmt("timed update value: ~p", [List]),

    1 = length(folsom_metrics:get_metric_value(<<"history">>)),
    1 = length(folsom_metrics:get_metric_value(historya)),

    ?debugFmt("checking meter~n", []),
    Meter = folsom_metrics:get_metric_value(meter),
    ?debugFmt("~p", [Meter]),
    ok = case proplists:get_value(one, Meter) of
        Value when Value > 1 ->
            ok;
        _ ->
            error
    end.

delete_metrics() ->
    11 = length(ets:tab2list(?FOLSOM_TABLE)),

    ok = folsom_metrics:delete_metric(counter),
    ok = folsom_metrics:delete_metric(<<"gauge">>),

    ok = folsom_metrics:delete_metric(<<"uniform">>),
    ok = folsom_metrics:delete_metric(exdec),
    ok = folsom_metrics:delete_metric(none),

    ok = folsom_metrics:delete_metric(<<"history">>),
    ok = folsom_metrics:delete_metric(historya),

    ok = folsom_metrics:delete_metric(nonea),
    ok = folsom_metrics:delete_metric(timed),
    ok = folsom_metrics:delete_metric(testcounter),

    1 = length(ets:tab2list(?METER_TABLE)),
    ok = folsom_metrics:delete_metric(meter),
    0 = length(ets:tab2list(?METER_TABLE)),

    0 = length(ets:tab2list(?FOLSOM_TABLE)).

vm_metrics() ->
    List1 = folsom_vm_metrics:get_memory(),
    true = lists:keymember(total, 1, List1),

    List2 = folsom_vm_metrics:get_statistics(),
    true = lists:keymember(context_switches, 1, List2),

    List3 = folsom_vm_metrics:get_system_info(),
    true = lists:keymember(allocated_areas, 1, List3),

    [{_, [{backtrace, _}| _]} | _] = folsom_vm_metrics:get_process_info(),

    [{_, [{name, _}| _]} | _] = folsom_vm_metrics:get_port_info().


counter_metric(Count, Counter) ->
    ok = folsom_metrics:new_counter(Counter),

    ?debugFmt("running ~p counter inc/dec rounds~n", [Count]),
    for(Count, Counter),

    Result = folsom_metrics:get_metric_value(Counter),
    ?debugFmt("counter result: ~p~n", [Result]),

    0 = Result.

ensure_meter_tick_exists(Name) ->
    {state, [{Name ,{interval, _}} | _]} = folsom_meter_timer_server:dump(),
    ok.

%% internal function

histogram_checks(List) ->
    ?debugFmt("checking histogram statistics", []),
    %?debugFmt("~p~n", [List]),
    1 = proplists:get_value(min, List),
    5000 = proplists:get_value(max, List),
    956.6 = proplists:get_value(arithmetic_mean, List),
    143.6822521631216 = proplists:get_value(geometric_mean, List),

    Value = proplists:get_value(harmonic_mean, List),
    ok = case Value - 7.57556627 of
             Diff when Diff < 0.00000001 ->
                 ok;
             _ ->
                 error
         end,

    200 = proplists:get_value(median, List),
    2412421.1555555556 = proplists:get_value(variance, List),
    1553.1970755688267 = proplists:get_value(standard_deviation, List),
    1.6945363114445593 = proplists:get_value(skewness, List),
    1.6710725994068278 = proplists:get_value(kurtosis, List),
    List1 = proplists:get_value(percentile, List),
    percentile_check(List1),
    List2 = proplists:get_value(histogram, List),
    histogram_check(List2).

histogram_co_checks(List) ->
    ?debugFmt("checking histogram covariance and etc statistics", []),
    %?debugFmt("~p~n", [List]),
    [
     {covariance,16539.0},
     {tau,1.0},
     {rho,0.7815638250437413},
     {r,1.0}
    ] = List.

percentile_check(List) ->
    1000 = proplists:get_value(75, List),
    5000 = proplists:get_value(95, List),
    5000 = proplists:get_value(99, List),
    5000 = proplists:get_value(999, List).

histogram_check(List) ->
    1 = proplists:get_value(1, List),
    1 = proplists:get_value(5, List),
    1 = proplists:get_value(10, List),
    0 = proplists:get_value(20, List),
    0 = proplists:get_value(30, List),
    0 = proplists:get_value(40, List),
    0 = proplists:get_value(50, List),
    1 = proplists:get_value(100, List),
    0 = proplists:get_value(150, List),
    1 = proplists:get_value(200, List),
    0 = proplists:get_value(250, List),
    0 = proplists:get_value(300, List),
    0 = proplists:get_value(350, List),
    0 = proplists:get_value(400, List),
    1 = proplists:get_value(500, List),
    1 = proplists:get_value(750, List),
    1 = proplists:get_value(1000, List),
    0 = proplists:get_value(1500, List),
    1 = proplists:get_value(2000, List),
    0 = proplists:get_value(3000, List),
    0 = proplists:get_value(4000, List),
    1 = proplists:get_value(5000, List),
    0 = proplists:get_value(10000, List),
    0 = proplists:get_value(20000, List),
    0 = proplists:get_value(30000, List),
    0 = proplists:get_value(50000, List),
    0 = proplists:get_value(99999999999999, List).

counter_inc_dec(Counter) ->
    ok = folsom_metrics:notify({Counter, {inc, 1}}),
    ok = folsom_metrics:notify({Counter, {dec, 1}}).

for(N, Counter) ->
    for(N, 0, Counter).
for(N, Count, _Counter) when N == Count ->
    ok;
for(N, LoopCount, Counter) ->
    counter_inc_dec(Counter),
    for(N, LoopCount + 1, Counter).
