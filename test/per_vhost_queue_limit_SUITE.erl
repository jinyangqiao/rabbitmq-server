%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License at
%% http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
%% License for the specific language governing rights and limitations
%% under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2011-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(per_vhost_queue_limit_SUITE).

-include_lib("common_test/include/ct.hrl").
-include_lib("amqp_client/include/amqp_client.hrl").
-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

-import(rabbit_ct_client_helpers, [open_unmanaged_connection/3,
                                   close_connection_and_channel/2]).

all() ->
    [
     {group, cluster_size_1}
     , {group, cluster_size_2}
    ].

groups() ->
    [
      {cluster_size_1, [], [
          most_basic_single_node_queue_count,
          single_node_single_vhost_queue_count,
          single_node_multiple_vhosts_queue_count,
          single_node_single_vhost_limit,
          single_node_single_vhost_zero_limit
        ]},
      {cluster_size_2, [], [
          most_basic_cluster_queue_count
        ]},
      {cluster_rename, [], [
          %% vhost_limit_after_node_renamed
        ]}
    ].

suite() ->
    [
      %% If a test hangs, no need to wait for 30 minutes.
      {timetrap, {minutes, 8}}
    ].

%% see partitions_SUITE
-define(DELAY, 9000).

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    rabbit_ct_helpers:run_setup_steps(Config, [
                                               fun rabbit_ct_broker_helpers:enable_dist_proxy_manager/1
                                              ]).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config).

init_per_group(cluster_size_1, Config) ->
    init_per_multinode_group(cluster_size_1, Config, 1);
init_per_group(cluster_size_2, Config) ->
    init_per_multinode_group(cluster_size_2, Config, 2);
init_per_group(cluster_rename, Config) ->
    init_per_multinode_group(cluster_rename, Config, 2).

init_per_multinode_group(Group, Config, NodeCount) ->
    Suffix = rabbit_ct_helpers:testcase_absname(Config, "", "-"),
    Config1 = rabbit_ct_helpers:set_config(Config, [
                                                    {rmq_nodes_count, NodeCount},
                                                    {rmq_nodename_suffix, Suffix}
      ]),
    case Group of
        cluster_rename ->
            % The broker is managed by {init,end}_per_testcase().
            Config1;
        _ ->
            rabbit_ct_helpers:run_steps(Config1,
              rabbit_ct_broker_helpers:setup_steps() ++
              rabbit_ct_client_helpers:setup_steps())
    end.

end_per_group(cluster_rename, Config) ->
    % The broker is managed by {init,end}_per_testcase().
    Config;
end_per_group(_Group, Config) ->
    rabbit_ct_helpers:run_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_testcase(vhost_limit_after_node_renamed = Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase),
    rabbit_ct_helpers:run_steps(Config,
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps());
init_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_started(Config, Testcase),
    Config.

end_per_testcase(vhost_limit_after_node_renamed = Testcase, Config) ->
    Config1 = ?config(save_config, Config),
    rabbit_ct_helpers:run_steps(Config1,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()),
    rabbit_ct_helpers:testcase_finished(Config1, Testcase);
end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).

%% -------------------------------------------------------------------
%% Test cases.
%% -------------------------------------------------------------------

most_basic_single_node_queue_count(Config) ->
    VHost = <<"queue-limits">>,
    set_up_vhost(Config, VHost),
    ?assertEqual(0, count_queues_in(Config, VHost)),
    Conn     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    declare_exclusive_queues(Ch, 10),
    ?assertEqual(10, count_queues_in(Config, VHost)),
    close_connection_and_channel(Conn, Ch),
    ?assertEqual(0, count_queues_in(Config, VHost)),
    rabbit_ct_broker_helpers:delete_vhost(Config, VHost).

single_node_single_vhost_queue_count(Config) ->
    VHost = <<"queue-limits">>,
    set_up_vhost(Config, VHost),
    ?assertEqual(0, count_queues_in(Config, VHost)),
    Conn     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch} = amqp_connection:open_channel(Conn),
    declare_exclusive_queues(Ch, 10),
    ?assertEqual(10, count_queues_in(Config, VHost)),
    declare_durable_queues(Ch, 10),
    ?assertEqual(20, count_queues_in(Config, VHost)),
    delete_durable_queues(Ch, 10),
    ?assertEqual(10, count_queues_in(Config, VHost)),
    close_connection_and_channel(Conn, Ch),
    ?assertEqual(0, count_queues_in(Config, VHost)),
    rabbit_ct_broker_helpers:delete_vhost(Config, VHost).

single_node_multiple_vhosts_queue_count(Config) ->
    VHost1 = <<"queue-limits1">>,
    VHost2 = <<"queue-limits2">>,
    set_up_vhost(Config, VHost1),
    set_up_vhost(Config, VHost2),

    ?assertEqual(0, count_queues_in(Config, VHost1)),
    ?assertEqual(0, count_queues_in(Config, VHost2)),

    Conn1     = open_unmanaged_connection(Config, 0, VHost1),
    {ok, Ch1} = amqp_connection:open_channel(Conn1),
    Conn2     = open_unmanaged_connection(Config, 0, VHost2),
    {ok, Ch2} = amqp_connection:open_channel(Conn2),

    declare_exclusive_queues(Ch1, 10),
    ?assertEqual(10, count_queues_in(Config, VHost1)),
    declare_durable_queues(Ch1, 10),
    ?assertEqual(20, count_queues_in(Config, VHost1)),
    delete_durable_queues(Ch1, 10),
    ?assertEqual(10, count_queues_in(Config, VHost1)),
    declare_exclusive_queues(Ch2, 30),
    ?assertEqual(30, count_queues_in(Config, VHost2)),
    close_connection_and_channel(Conn1, Ch1),
    ?assertEqual(0, count_queues_in(Config, VHost1)),
    close_connection_and_channel(Conn2, Ch2),
    ?assertEqual(0, count_queues_in(Config, VHost2)),
    rabbit_ct_broker_helpers:delete_vhost(Config, VHost1),
    rabbit_ct_broker_helpers:delete_vhost(Config, VHost2).

most_basic_cluster_queue_count(Config) ->
    VHost = <<"queue-limits">>,
    set_up_vhost(Config, VHost),
    ?assertEqual(0, count_queues_in(Config, VHost, 0)),
    ?assertEqual(0, count_queues_in(Config, VHost, 1)),

    Conn1     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch1} = amqp_connection:open_channel(Conn1),
    declare_exclusive_queues(Ch1, 10),
    ?assertEqual(10, count_queues_in(Config, VHost, 0)),
    ?assertEqual(10, count_queues_in(Config, VHost, 1)),

    Conn2     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch2} = amqp_connection:open_channel(Conn1),
    declare_exclusive_queues(Ch2, 15),
    ?assertEqual(25, count_queues_in(Config, VHost, 0)),
    ?assertEqual(25, count_queues_in(Config, VHost, 1)),
    close_connection_and_channel(Conn1, Ch1),
    close_connection_and_channel(Conn2, Ch2),
    ?assertEqual(0, count_queues_in(Config, VHost, 0)),
    ?assertEqual(0, count_queues_in(Config, VHost, 1)),
    rabbit_ct_broker_helpers:delete_vhost(Config, VHost).

single_node_single_vhost_limit(Config) ->
    single_node_single_vhost_limit_with(Config, 5),
    single_node_single_vhost_limit_with(Config, 10).
single_node_single_vhost_zero_limit(Config) ->
    VHost = <<"queue-limits">>,
    set_up_vhost(Config, VHost),
    ?assertEqual(0, count_queues_in(Config, VHost)),

    Conn1     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch1} = amqp_connection:open_channel(Conn1),

    set_vhost_queue_limit(Config, VHost, 0),

    try
        amqp_channel:call(Ch1, #'queue.declare'{queue     = <<"">>,
                                                exclusive = true}),
        ok
    catch _:{{shutdown, {server_initiated_close, 406, _}}, _} ->
        %% expected
        ok
    end,

    Conn2     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch2} = amqp_connection:open_channel(Conn2),

    %% lift the limit
    set_vhost_queue_limit(Config, VHost, -1),
    lists:foreach(fun (_) ->
                    #'queue.declare_ok'{queue = _} =
                        amqp_channel:call(Ch2, #'queue.declare'{queue     = <<"">>,
                                                               exclusive = true})
                  end, lists:seq(1, 100)),

    rabbit_ct_broker_helpers:delete_vhost(Config, VHost).

single_node_single_vhost_limit_with(Config, WatermarkLimit) ->
    VHost = <<"queue-limits">>,
    set_up_vhost(Config, VHost),
    ?assertEqual(0, count_queues_in(Config, VHost)),

    set_vhost_queue_limit(Config, VHost, 3),
    Conn     = open_unmanaged_connection(Config, 0, VHost),
    {ok, Ch} = amqp_connection:open_channel(Conn),

    set_vhost_queue_limit(Config, VHost, WatermarkLimit),
    lists:foreach(fun (_) ->
                    #'queue.declare_ok'{queue = _} =
                        amqp_channel:call(Ch, #'queue.declare'{queue     = <<"">>,
                                                               exclusive = true})
                  end, lists:seq(1, WatermarkLimit)),

    try
        amqp_channel:call(Ch, #'queue.declare'{queue     = <<"">>,
                                               exclusive = true}),
        ok
    catch _:{{shutdown, {server_initiated_close, 406, _}}, _} ->
        %% expected
        ok
    end,

    rabbit_ct_broker_helpers:delete_vhost(Config, VHost).

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

set_up_vhost(Config, VHost) ->
    rabbit_ct_broker_helpers:add_vhost(Config, VHost),
    rabbit_ct_broker_helpers:set_full_permissions(Config, <<"guest">>, VHost),
    set_vhost_queue_limit(Config, VHost, -1).

set_vhost_queue_limit(Config, VHost, Count) ->
    set_vhost_queue_limit(Config, 0, VHost, Count).

set_vhost_queue_limit(Config, NodeIndex, VHost, Count) ->
    Node  = rabbit_ct_broker_helpers:get_node_config(
              Config, NodeIndex, nodename),
    rabbit_ct_broker_helpers:control_action(
      set_vhost_limits, Node,
      ["{\"max-queues\": " ++ integer_to_list(Count) ++ "}"],
      [{"-p", binary_to_list(VHost)}]).

count_queues_in(Config, VHost) ->
    count_queues_in(Config, VHost, 0).
count_queues_in(Config, VHost, NodeIndex) ->
    timer:sleep(200),
    rabbit_ct_broker_helpers:rpc(Config, NodeIndex,
                                 rabbit_amqqueue,
                                 count, [VHost]).

declare_exclusive_queues(Ch, N) ->
    lists:foreach(fun (_) ->
                          amqp_channel:call(Ch,
                                            #'queue.declare'{queue     = <<"">>,
                                                             exclusive = true})
                  end,
                  lists:seq(1, N)).

declare_durable_queues(Ch, N) ->
    lists:foreach(fun (I) ->
                          amqp_channel:call(Ch,
                                            #'queue.declare'{queue     = durable_queue_name(I),
                                                             exclusive = false,
                                                             durable   = true})
                  end,
                  lists:seq(1, N)).

delete_durable_queues(Ch, N) ->
    lists:foreach(fun (I) ->
                          amqp_channel:call(Ch,
                                            #'queue.delete'{queue = durable_queue_name(I)})
                  end,
                  lists:seq(1, N)).

durable_queue_name(N) when is_integer(N) ->
    iolist_to_binary(io_lib:format("queue-limits-durable-~p", [N])).
